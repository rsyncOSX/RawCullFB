import Foundation
import Testing
@testable import RawCullFB

@Suite("CLIP feature")
struct CLIPFeatureTests {
    @Test("Semantic result limit defaults to 50")
    func defaultResultLimit() {
        #expect(BrowserSettings().semanticSearchLimit == 50)
    }

    @Test("Decoded semantic result limit is bounded")
    func decodedResultLimitIsBounded() throws {
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

    @Test("Index paths are hidden and model-specific")
    func indexPathsAreModelSpecific() {
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

    @Test("Only current or partially outdated indexes allow search")
    func indexStatusSearchAvailability() {
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

    @Test("Discovery is recursive and ignores hidden or unsupported files")
    func recursiveDiscovery() throws {
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

    @Test("SigLIP 2 bundle indexes and searches through RawCullFB")
    func siglip2EndToEnd() async throws {
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

        #expect(summary.discovered == reference.images.count)
        #expect(summary.indexed == reference.images.count)
        #expect(summary.failures.isEmpty)
        #expect(results.count == reference.images.count)
        #expect(await engine.hasCompatibleIndex())
    }
}

private struct SigLIP2SearchReference: Decodable {
    struct ImageItem: Decodable {
        let path: String
    }

    let images: [ImageItem]
}
