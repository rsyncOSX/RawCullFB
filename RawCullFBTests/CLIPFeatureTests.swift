import Foundation
import PhotoAIContracts
@testable import RawCullFB
import Testing

@Suite("CLIP feature")
struct CLIPFeatureTests {
    @Test
    func `Managed CLIP catalog matches RawCull asset packs`() {
        let catalog = CLIPModelDownloadCatalog.production

        #expect(catalog.models.map(\.id) == [.clipDataComp, .clipOpenAI])
        #expect(
            catalog.descriptor(for: .clipDataComp)?.assetPackID
                == "no.blogspot.RawCull.models.clip-datacomp",
        )
        #expect(
            catalog.descriptor(for: .clipOpenAI)?.assetPackID
                == "no.blogspot.RawCull.models.clip-openai",
        )
        #expect(
            catalog.descriptor(for: .clipDataComp)?.assetPackModelPath
                == "Models/CLIP-DataComp",
        )
        #expect(
            catalog.descriptor(for: .clipOpenAI)?.assetPackModelPath
                == "Models/CLIP-OpenAI",
        )
    }

    @Test
    func `OpenAI is the default and managed CLIP selection is persisted`() throws {
        #expect(BrowserSettings().selectedCLIPModel == .openAI)

        let decoded = try JSONDecoder().decode(
            BrowserSettings.self,
            from: Data(#"{"selectedCLIPModel":"data-comp"}"#.utf8),
        )

        #expect(decoded.selectedCLIPModel == .dataComp)
    }

    @Test
    func `Semantic result limit defaults to 50`() {
        #expect(BrowserSettings().semanticSearchLimit == 50)
    }

    @Test
    func `Decoded semantic result limit is bounded`() throws {
        let tooSmall = try JSONDecoder().decode(
            BrowserSettings.self,
            from: Data(#"{"semanticSearchLimit":-20}"#.utf8),
        )
        let tooLarge = try JSONDecoder().decode(
            BrowserSettings.self,
            from: Data(#"{"semanticSearchLimit":900}"#.utf8),
        )

        #expect(tooSmall.semanticSearchLimit == 10)
        #expect(tooLarge.semanticSearchLimit == 500)
    }

    @Test
    func `Index paths are hidden and model-specific`() {
        let directory = URL(filePath: "/tmp/photos", directoryHint: .isDirectory)
        let first = CLIPIndexPaths.defaultIndexURL(
            directory: directory,
            modelFingerprint: "model-a",
        )
        let second = CLIPIndexPaths.defaultIndexURL(
            directory: directory,
            modelFingerprint: "model-b",
        )

        #expect(first != second)
        #expect(first.deletingLastPathComponent().lastPathComponent == ".clipbench")
        #expect(first.pathExtension == "clipindex")
    }

    @Test
    func `Only current or partially outdated indexes allow search`() {
        let directory = URL(filePath: "/tmp/photos", directoryHint: .isDirectory)
        let updatedAt = Date(timeIntervalSince1970: 1)
        let valid = CLIPIndexStatus.valid(directory: directory, indexed: 10, updatedAt: updatedAt)
        let needsUpdate = CLIPIndexStatus.needsUpdate(
            directory: directory,
            indexed: 10,
            missing: 2,
            changed: 1,
            removed: 0,
            updatedAt: updatedAt,
        )

        #expect(valid.allowsSearch)
        #expect(!valid.recommendsUpdate)
        #expect(needsUpdate.allowsSearch)
        #expect(needsUpdate.recommendsUpdate)
        #expect(!CLIPIndexStatus.notFound(directory).allowsSearch)
        #expect(!CLIPIndexStatus.invalid(directory: directory, reason: "bad index").allowsSearch)
    }

    @Test
    func `Discovery is recursive and ignores hidden or unsupported files`() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RawCullFBTests-\(UUID().uuidString)", isDirectory: true)
        let nested = root.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try Data([0]).write(to: root.appendingPathComponent("first.jpg"))
        try Data([0]).write(to: nested.appendingPathComponent("second.ARW"))
        try Data([0]).write(to: root.appendingPathComponent("notes.txt"))
        try Data([0]).write(to: root.appendingPathComponent(".hidden.jpg"))

        let discovered = try CLIPImageDiscovery.sources(in: root)
        let names = Set(discovered.map(\.displayName))

        #expect(names == ["first.jpg", "second.ARW"])
    }

    @Test
    func `Image similarity ranks indexed neighbors and excludes its anchor`() throws {
        let anchor = try indexedEntry(path: "/photos/anchor.jpg", values: [1, 0])
        let nearest = try indexedEntry(path: "/photos/nearest.jpg", values: [0.9, 0.1])
        let furthest = try indexedEntry(path: "/photos/furthest.jpg", values: [0, 1])
        let index = CLIPPersistedIndex(
            backend: testBackend,
            entries: [furthest, anchor, nearest],
        )

        let results = try CLIPSimilaritySearch.results(
            in: index,
            anchorURL: anchor.source.url,
            limit: 10,
        )

        #expect(results.map(\.fileName) == ["nearest.jpg", "furthest.jpg"])
        #expect(results.map(\.rank) == [1, 2])
        #expect(results.allSatisfy { $0.path != anchor.source.url.path })
    }

    @Test
    func `Local CLIP bundle returns semantic search results`() async throws {
        guard let bundlePath = ProcessInfo.processInfo.environment["CLIP_COREAI_BUNDLE"] else {
            return
        }
        let load = await CLIPModelManager().load(
            url: URL(filePath: bundlePath, directoryHint: .isDirectory),
        )
        guard let provider = load.provider else {
            Issue.record("RawCullFB rejected the CLIP model bundle")
            return
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RawCullFBSemanticSearch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("images/background.png")
        try FileManager.default.copyItem(
            at: fixture,
            to: root.appendingPathComponent("fixture.png"),
        )

        let engine = CLIPSearchEngine(
            provider: provider,
            indexStore: CLIPIndexStore(
                fileURL: CLIPIndexPaths.defaultIndexURL(
                    directory: root,
                    modelFingerprint: provider.backendDescriptor.modelFingerprint,
                ),
            ),
        )
        let summary = try await engine.synchronize(directory: root)
        let results = try await engine.search(text: "muskox", limit: 10)

        #expect(summary.indexed == 1)
        #expect(results.count == 1)
        #expect(results.first?.fileName == "fixture.png")
    }

    @Test
    func `SigLIP 2 bundle indexes and searches through RawCullFB`() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let bundlePath = environment["SIGLIP2_COREAI_BUNDLE"],
              let referencePath = environment["SIGLIP2_REFERENCE"]
        else {
            return
        }

        let load = await CLIPModelManager().load(
            url: URL(filePath: bundlePath, directoryHint: .isDirectory),
        )
        guard case let .available(_, _, modelName) = load.status,
              let provider = load.provider
        else {
            Issue.record("RawCullFB rejected the SigLIP 2 model bundle")
            return
        }
        #expect(modelName == "SigLIP2-Base-Patch16-256")
        #expect(provider.backendDescriptor.backend == "siglip2")

        let referenceURL = URL(filePath: referencePath)
        let reference = try JSONDecoder().decode(
            SigLIP2SearchReference.self,
            from: Data(contentsOf: referenceURL),
        )
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RawCullFBSigLIP2-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        for (offset, item) in reference.images.enumerated() {
            let source = URL(
                filePath: item.path,
                directoryHint: .notDirectory,
                relativeTo: referenceURL.deletingLastPathComponent(),
            ).standardizedFileURL
            try FileManager.default.copyItem(
                at: source,
                to: root.appendingPathComponent("fixture-\(offset).jpg"),
            )
        }

        let indexURL = CLIPIndexPaths.defaultIndexURL(
            directory: root,
            modelFingerprint: provider.backendDescriptor.modelFingerprint,
        )
        let engine = CLIPSearchEngine(
            provider: provider,
            indexStore: CLIPIndexStore(fileURL: indexURL),
        )
        let summary = try await engine.synchronize(directory: root)
        let results = try await engine.search(text: "puffins portrait", limit: 10)
        let similar = try await engine.search(
            similarTo: root.appendingPathComponent("fixture-0.jpg"),
            limit: 10,
        )

        #expect(summary.discovered == reference.images.count)
        #expect(summary.indexed == reference.images.count)
        #expect(summary.failures.isEmpty)
        #expect(results.count == reference.images.count)
        #expect(similar.count == max(0, reference.images.count - 1))
        #expect(await engine.hasCompatibleIndex())
    }

    private var testBackend: SimilarityBackendDescriptor {
        SimilarityBackendDescriptor(
            backend: "clip",
            modelFingerprint: testModel.artifactIdentifier,
            representation: "embedding",
            preprocessingVersion: "1",
            normalizationVersion: "1",
            configurationVersion: "1",
        )
    }

    private var testModel: ModelIdentity {
        ModelIdentity(family: "clip", name: "test", assetName: "test")
    }

    private func indexedEntry(path: String, values: [Float]) throws -> CLIPIndexEntry {
        let url = URL(filePath: path)
        let source = AIImageSource(id: UUID(), url: url, displayName: url.lastPathComponent)
        let fingerprint = SourceFingerprint(
            standardizedPath: url.standardizedFileURL.path,
            fileSize: nil,
            modificationDate: nil,
        )
        let embedding = ImageEmbedding(
            backend: testBackend.backend,
            modelIdentity: testModel,
            values: values,
        )
        let artifact = try SimilarityArtifact(
            descriptor: SimilarityArtifactDescriptor(
                backend: testBackend,
                dimensions: values.count,
                sourceFingerprint: fingerprint,
            ),
            payload: JSONEncoder().encode(embedding),
        )
        return CLIPIndexEntry(source: source, fingerprint: fingerprint, artifact: artifact)
    }
}

private struct SigLIP2SearchReference: Decodable {
    struct ImageItem: Decodable {
        let path: String
    }

    let images: [ImageItem]
}
