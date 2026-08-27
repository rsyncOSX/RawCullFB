import CoreAICLIPBackend
import CryptoKit
import Foundation
import PhotoAIContracts
import PhotoAIWorkflows

nonisolated enum CLIPFeatureError: Error, CustomStringConvertible, Sendable {
    case cannotReadDirectory(String)
    case cannotDecodeImage(String)
    case emptyQuery
    case imageNotIndexed(String)
    case missingCompatibleIndex
    case modelNotConfigured

    var description: String {
        switch self {
        case let .cannotReadDirectory(path): "Cannot read image directory: \(path)"
        case let .cannotDecodeImage(path): "Cannot decode image: \(path)"
        case .emptyQuery: "Enter a semantic search description."
        case let .imageNotIndexed(name): "Index \(name) before searching for similar images."
        case .missingCompatibleIndex: "Index the selected folder with the current model before searching."
        case .modelNotConfigured: "Choose and verify a compatible CLIP model in Settings first."
        }
    }
}

nonisolated struct CLIPIndexSummary: Equatable, Sendable {
    let discovered: Int
    let reused: Int
    let indexed: Int
    let failures: [String]
}

nonisolated struct CLIPIndexingProgress: Equatable, Sendable {
    let completed: Int
    let total: Int
    let currentFileName: String?
}

nonisolated enum CLIPIndexStatus: Equatable, Sendable {
    case noFolderSelected
    case modelRequired
    case checking(URL)
    case notFound(URL)
    case valid(directory: URL, indexed: Int, updatedAt: Date)
    case needsUpdate(
        directory: URL,
        indexed: Int,
        missing: Int,
        changed: Int,
        removed: Int,
        updatedAt: Date,
    )
    case invalid(directory: URL, reason: String)

    var allowsSearch: Bool {
        switch self {
        case .valid, .needsUpdate: true
        case .noFolderSelected, .modelRequired, .checking, .notFound, .invalid: false
        }
    }

    var recommendsUpdate: Bool {
        if case .needsUpdate = self {
            true
        } else {
            false
        }
    }

    var indexFileExists: Bool? {
        switch self {
        case .valid, .needsUpdate, .invalid: true
        case .notFound: false
        case .noFolderSelected, .modelRequired, .checking: nil
        }
    }
}

nonisolated struct CLIPSearchResult: Equatable, Identifiable, Sendable {
    let rank: Int
    let score: Float
    let fileName: String
    let path: String

    var id: String {
        path
    }

    var url: URL {
        URL(filePath: path)
    }
}

nonisolated struct CLIPSimilarityNeighbor: Equatable, Sendable {
    let rank: Int
    let distance: Float
    let fileName: String
    let path: String
}

nonisolated struct CLIPSimilarityAnchorResult: Equatable, Sendable {
    let fileName: String
    let path: String
    let neighbors: [CLIPSimilarityNeighbor]
}

nonisolated struct CLIPSimilarityEvaluation: Equatable, Sendable {
    let imageCount: Int
    let pairComparisonCount: Int
    let incompatiblePairCount: Int
    let neighborLimit: Int
    let anchors: [CLIPSimilarityAnchorResult]
}

final nonisolated class CLIPSearchEngine: Sendable {
    let provider: CoreAICLIPProvider
    let indexStore: CLIPIndexStore
    let decoder: CLIPImageDecoder
    let concurrencyLimit: Int

    init(
        provider: CoreAICLIPProvider,
        indexStore: CLIPIndexStore,
        decoder: CLIPImageDecoder = CLIPImageDecoder(),
        concurrencyLimit: Int = 2,
    ) {
        self.provider = provider
        self.indexStore = indexStore
        self.decoder = decoder
        self.concurrencyLimit = max(1, concurrencyLimit)
    }

    func hasCompatibleIndex() async -> Bool {
        await (try? indexStore.load(compatibleWith: provider.backendDescriptor)) != nil
    }

    @concurrent func validateIndex(directory: URL) async -> CLIPIndexStatus {
        let standardizedDirectory = directory.standardizedFileURL
        guard FileManager.default.fileExists(atPath: indexStore.fileURL.path) else {
            return .notFound(standardizedDirectory)
        }

        do {
            guard let index = try await indexStore.load(
                compatibleWith: provider.backendDescriptor,
            ) else {
                return .invalid(
                    directory: standardizedDirectory,
                    reason: "The index is not compatible with the selected CLIP model or index format.",
                )
            }
            try Task.checkCancellation()
            let sources = try CLIPImageDiscovery.sources(in: standardizedDirectory)
            try Task.checkCancellation()

            var entriesByPath: [String: CLIPIndexEntry] = [:]
            for entry in index.entries {
                entriesByPath[entry.fingerprint.standardizedPath] = entry
            }

            var currentPaths: Set<String> = []
            var missing = 0
            var changed = 0
            for source in sources {
                try Task.checkCancellation()
                let fingerprint = SourceFingerprint(source: source)
                currentPaths.insert(fingerprint.standardizedPath)
                guard let entry = entriesByPath[fingerprint.standardizedPath] else {
                    missing += 1
                    continue
                }
                if entry.fingerprint != fingerprint
                    || !entry.artifact.descriptor.matches(provider.backendDescriptor) {
                    changed += 1
                }
            }

            let removed = entriesByPath.keys.count { !currentPaths.contains($0) }
            if missing == 0, changed == 0, removed == 0 {
                return .valid(
                    directory: standardizedDirectory,
                    indexed: index.entries.count,
                    updatedAt: index.updatedAt,
                )
            }
            return .needsUpdate(
                directory: standardizedDirectory,
                indexed: index.entries.count,
                missing: missing,
                changed: changed,
                removed: removed,
                updatedAt: index.updatedAt,
            )
        } catch is CancellationError {
            return .checking(standardizedDirectory)
        } catch {
            return .invalid(
                directory: standardizedDirectory,
                reason: String(describing: error),
            )
        }
    }

    @concurrent func synchronize(
        directory: URL,
        progress: (@Sendable (CLIPIndexingProgress) async -> Void)? = nil,
    ) async throws -> CLIPIndexSummary {
        let sources = try CLIPImageDiscovery.sources(in: directory)
        let oldIndex = try await indexStore.load(compatibleWith: provider.backendDescriptor)
        let oldEntries = Dictionary(
            uniqueKeysWithValues: (oldIndex?.entries ?? []).map {
                ($0.fingerprint.standardizedPath, $0)
            },
        )
        var entries: [CLIPIndexEntry] = []
        var pending: [AIImageSource] = []

        for source in sources {
            try Task.checkCancellation()
            let fingerprint = SourceFingerprint(source: source)
            if let existing = oldEntries[fingerprint.standardizedPath],
               existing.fingerprint == fingerprint,
               existing.artifact.descriptor.matches(provider.backendDescriptor) {
                entries.append(CLIPIndexEntry(
                    source: source,
                    fingerprint: fingerprint,
                    artifact: existing.artifact,
                ))
            } else {
                pending.append(source)
            }
        }

        if !pending.isEmpty {
            let pendingSources = pending
            let indexer = SimilarityArtifactIndexer(
                primaryProvider: provider,
                decoder: decoder,
                concurrencyLimit: concurrencyLimit,
            )
            let result = try await indexer.index(pendingSources) { update in
                let currentName = pendingSources.first {
                    $0.id == update.currentSourceID
                }?.displayName
                await progress?(CLIPIndexingProgress(
                    completed: update.completed,
                    total: update.total,
                    currentFileName: currentName,
                ))
            }
            for source in pendingSources {
                guard let artifact = result.artifacts[source.id] else { continue }
                entries.append(CLIPIndexEntry(
                    source: source,
                    fingerprint: SourceFingerprint(source: source),
                    artifact: artifact,
                ))
            }
            entries.sort { $0.source.url.path.localizedStandardCompare($1.source.url.path) == .orderedAscending }
            try await indexStore.save(CLIPPersistedIndex(
                backend: provider.backendDescriptor,
                entries: entries,
            ))
            return CLIPIndexSummary(
                discovered: sources.count,
                reused: sources.count - pendingSources.count,
                indexed: result.artifacts.count,
                failures: result.failures.map { "\($0.source.displayName): \($0.message)" },
            )
        }

        try await indexStore.save(CLIPPersistedIndex(
            backend: provider.backendDescriptor,
            entries: entries,
        ))
        return CLIPIndexSummary(
            discovered: sources.count,
            reused: entries.count,
            indexed: 0,
            failures: [],
        )
    }

    @concurrent func search(text: String, limit: Int) async throws -> [CLIPSearchResult] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CLIPFeatureError.emptyQuery
        }
        guard let index = try await indexStore.load(compatibleWith: provider.backendDescriptor) else {
            throw CLIPFeatureError.missingCompatibleIndex
        }
        let textEmbedding = try await provider.embedding(for: text)
        let scored = try index.entries.map { entry in
            try (entry, provider.similarity(image: entry.artifact, text: textEmbedding))
        }
        .sorted {
            if $0.1 == $1.1 {
                return $0.0.source.url.path < $1.0.source.url.path
            }
            return $0.1 > $1.1
        }
        return scored.prefix(max(0, limit)).enumerated().map { offset, item in
            CLIPSearchResult(
                rank: offset + 1,
                score: item.1,
                fileName: item.0.source.displayName,
                path: item.0.source.url.path,
            )
        }
    }

    @concurrent func search(similarTo imageURL: URL, limit: Int) async throws -> [CLIPSearchResult] {
        guard let index = try await indexStore.load(compatibleWith: provider.backendDescriptor) else {
            throw CLIPFeatureError.missingCompatibleIndex
        }
        return try CLIPSimilaritySearch.results(in: index, anchorURL: imageURL, limit: limit)
    }

    @concurrent func evaluateImageSimilarity(
        neighborLimit: Int = 10,
    ) async throws -> CLIPSimilarityEvaluation {
        guard let index = try await indexStore.load(compatibleWith: provider.backendDescriptor) else {
            throw CLIPFeatureError.missingCompatibleIndex
        }

        let entries = index.entries.sorted {
            $0.source.url.path.localizedStandardCompare($1.source.url.path) == .orderedAscending
        }
        let decoder = JSONDecoder()
        let embeddings = try entries.map { entry in
            let embedding = try decoder.decode(ImageEmbedding.self, from: entry.artifact.payload)
            guard EmbeddingArtifact(
                descriptor: entry.artifact.descriptor,
                embedding: embedding,
            ).isInternallyConsistent else {
                throw CLIPSimilarityArtifactError.invalidPayload(
                    "The vector payload does not match its artifact descriptor.",
                )
            }
            return embedding
        }
        let limit = max(0, min(neighborLimit, max(0, entries.count - 1)))
        var candidates = Array(
            repeating: [(entry: CLIPIndexEntry, distance: Float)](),
            count: entries.count,
        )
        var pairComparisonCount = 0
        var incompatiblePairCount = 0

        guard entries.count > 1 else {
            return CLIPSimilarityEvaluation(
                imageCount: entries.count,
                pairComparisonCount: 0,
                incompatiblePairCount: 0,
                neighborLimit: limit,
                anchors: entries.map {
                    CLIPSimilarityAnchorResult(
                        fileName: $0.source.displayName,
                        path: $0.source.url.path,
                        neighbors: [],
                    )
                },
            )
        }

        for leftIndex in 0 ..< entries.count - 1 {
            try Task.checkCancellation()
            for rightIndex in leftIndex + 1 ..< entries.count {
                pairComparisonCount += 1
                guard let distance = embeddings[leftIndex].cosineDistance(
                    to: embeddings[rightIndex],
                ) else {
                    incompatiblePairCount += 1
                    continue
                }
                insertCandidate(
                    (entries[rightIndex], distance),
                    into: &candidates[leftIndex],
                    limit: limit,
                )
                insertCandidate(
                    (entries[leftIndex], distance),
                    into: &candidates[rightIndex],
                    limit: limit,
                )
            }
        }

        let anchors = entries.indices.map { index in
            let sorted = candidates[index].sorted {
                if $0.distance == $1.distance {
                    return $0.entry.source.url.path < $1.entry.source.url.path
                }
                return $0.distance < $1.distance
            }
            let neighbors = sorted.prefix(limit).enumerated().map { offset, candidate in
                CLIPSimilarityNeighbor(
                    rank: offset + 1,
                    distance: candidate.distance,
                    fileName: candidate.entry.source.displayName,
                    path: candidate.entry.source.url.path,
                )
            }
            return CLIPSimilarityAnchorResult(
                fileName: entries[index].source.displayName,
                path: entries[index].source.url.path,
                neighbors: neighbors,
            )
        }

        return CLIPSimilarityEvaluation(
            imageCount: entries.count,
            pairComparisonCount: pairComparisonCount,
            incompatiblePairCount: incompatiblePairCount,
            neighborLimit: limit,
            anchors: anchors,
        )
    }

    private func insertCandidate(
        _ candidate: (entry: CLIPIndexEntry, distance: Float),
        into candidates: inout [(entry: CLIPIndexEntry, distance: Float)],
        limit: Int,
    ) {
        guard limit > 0 else { return }
        candidates.append(candidate)
        guard candidates.count > limit else { return }
        let worstIndex = candidates.indices.max { left, right in
            if candidates[left].distance == candidates[right].distance {
                return candidates[left].entry.source.url.path
                    < candidates[right].entry.source.url.path
            }
            return candidates[left].distance < candidates[right].distance
        }
        if let worstIndex {
            candidates.remove(at: worstIndex)
        }
    }
}

nonisolated enum CLIPIndexPaths {
    static func containsIndex(in directory: URL) -> Bool {
        let indexDirectory = directory.appendingPathComponent(".clipbench", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: indexDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
        ) else { return false }

        return files.contains { fileURL in
            guard fileURL.pathExtension.caseInsensitiveCompare("clipindex") == .orderedSame else {
                return false
            }
            return (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }
    }

    static func defaultIndexURL(directory: URL, modelFingerprint: String) -> URL {
        let digest = SHA256.hash(data: Data(modelFingerprint.utf8))
        let hash = digest.prefix(16).map { String(format: "%02x", $0) }.joined()
        return directory
            .appendingPathComponent(".clipbench", isDirectory: true)
            .appendingPathComponent("clip-\(hash).clipindex")
    }
}
