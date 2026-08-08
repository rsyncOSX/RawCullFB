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
}
