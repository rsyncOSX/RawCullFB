import Foundation
import Testing
@testable import RawCullFB

@Suite("Semantic search test runner")
struct SemanticSearchTestRunnerTests {
    @Test("Runs queries sequentially and updates a model-prefixed report")
    func runsSequentiallyAndUpdatesReport() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "RawCullFBSemanticTest-\(UUID().uuidString)",
            isDirectory: true,
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = """
        # Basic recognition
        a dog

        a red car
        a city street at night
        """
        try Data(input.utf8).write(
            to: directory.appendingPathComponent(SemanticSearchTestRunner.inputFileName),
        )

        let recorder = SemanticTestSearchRecorder(directory: directory)
        let reportRecorder = SemanticTestReportRecorder()
        let outcome = try await SemanticSearchTestRunner.run(
            directory: directory,
            modelName: "SigLIP 2/Test",
            modelFingerprint: "fingerprint-123",
            resultLimit: 10,
            search: { query, limit in
                try await recorder.search(query: query, limit: limit)
            },
            progress: { progress in
                await reportRecorder.capture(progress)
            },
        )

        #expect(outcome.completedQueryCount == 3)
        #expect(outcome.totalQueryCount == 3)
        #expect(!outcome.wasCancelled)
        #expect(outcome.resultFileURL.lastPathComponent == "SigLIP-2-Test-semantic-test-results.txt")
        let recordedQueries = await recorder.recordedQueries
        let recordedLimits = await recorder.recordedLimits
        #expect(recordedQueries == [
            "a dog",
            "a red car",
            "a city street at night",
        ])
        #expect(recordedLimits == [10, 10, 10])

        let report = try String(contentsOf: outcome.resultFileURL, encoding: .utf8)
        #expect(report.contains("model\tSigLIP 2/Test"))
        #expect(report.contains("status\tcompleted"))
        #expect(report.contains("completed_queries\t3"))
        #expect(report.contains("QUERY\t1\ta dog"))
        #expect(report.contains("1\t0.75\ta dog.jpg\timages/a dog.jpg"))

        let snapshots = await reportRecorder.snapshots
        #expect(snapshots.count == 4)
        #expect(snapshots.map(\.completedQueryCount) == [0, 1, 2, 3])
        #expect(snapshots.dropFirst().allSatisfy { $0.reportExists })
    }

    @Test("Records a failed query and continues")
    func recordsFailureAndContinues() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "RawCullFBSemanticFailure-\(UUID().uuidString)",
            isDirectory: true,
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("first\nfail\nlast\n".utf8).write(
            to: directory.appendingPathComponent(SemanticSearchTestRunner.inputFileName),
        )

        let outcome = try await SemanticSearchTestRunner.run(
            directory: directory,
            modelName: "OpenAI CLIP",
            modelFingerprint: "openai",
            resultLimit: 5,
            search: { query, _ in
                if query == "fail" { throw SemanticTestFailure.expected }
                return []
            },
        )

        #expect(outcome.completedQueryCount == 3)
        let report = try String(contentsOf: outcome.resultFileURL, encoding: .utf8)
        #expect(report.contains("QUERY\t2\tfail"))
        #expect(report.contains("error\texpected"))
        #expect(report.contains("QUERY\t3\tlast"))
        #expect(report.contains("status\tcompleted"))
    }
}

private enum SemanticTestFailure: Error {
    case expected
}

private actor SemanticTestSearchRecorder {
    private(set) var recordedQueries: [String] = []
    private(set) var recordedLimits: [Int] = []
    let directory: URL

    init(directory: URL) {
        self.directory = directory
    }

    func search(query: String, limit: Int) throws -> [CLIPSearchResult] {
        recordedQueries.append(query)
        recordedLimits.append(limit)
        return [CLIPSearchResult(
            rank: 1,
            score: 0.75,
            fileName: "\(query).jpg",
            path: directory
                .appendingPathComponent("images")
                .appendingPathComponent("\(query).jpg")
                .path,
        )]
    }
}

private actor SemanticTestReportRecorder {
    struct Snapshot: Sendable {
        let completedQueryCount: Int
        let reportExists: Bool
    }

    private(set) var snapshots: [Snapshot] = []

    func capture(_ progress: SemanticSearchTestProgress) {
        snapshots.append(Snapshot(
            completedQueryCount: progress.completedQueryCount,
            reportExists: FileManager.default.fileExists(
                atPath: progress.resultFileURL.path,
            ),
        ))
    }
}
