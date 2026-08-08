import Foundation
import PhotoAIContracts

nonisolated struct CLIPIndexEntry: Codable, Equatable, Sendable {
    let source: AIImageSource
    let fingerprint: SourceFingerprint
    let artifact: SimilarityArtifact
}

nonisolated struct CLIPPersistedIndex: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let backend: SimilarityBackendDescriptor
    let entries: [CLIPIndexEntry]
    let updatedAt: Date

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        backend: SimilarityBackendDescriptor,
        entries: [CLIPIndexEntry],
        updatedAt: Date = .now,
    ) {
        self.schemaVersion = schemaVersion
        self.backend = backend
        self.entries = entries
        self.updatedAt = updatedAt
    }
}

actor CLIPIndexStore {
    nonisolated let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func load(
        compatibleWith backend: SimilarityBackendDescriptor,
    ) throws -> CLIPPersistedIndex? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        let index = try PropertyListDecoder().decode(CLIPPersistedIndex.self, from: data)
        guard index.schemaVersion == CLIPPersistedIndex.currentSchemaVersion,
              index.backend == backend
        else {
            return nil
        }
        return index
    }

    func save(_ index: CLIPPersistedIndex) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
        )
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try encoder.encode(index).write(to: fileURL, options: .atomic)
    }
}

nonisolated extension SimilarityArtifactDescriptor {
    func matches(_ backend: SimilarityBackendDescriptor) -> Bool {
        self.backend == backend.backend
            && modelFingerprint == backend.modelFingerprint
            && representation == backend.representation
            && preprocessingVersion == backend.preprocessingVersion
            && normalizationVersion == backend.normalizationVersion
            && configurationVersion == backend.configurationVersion
            && schemaVersion == Self.currentSchemaVersion
    }
}
