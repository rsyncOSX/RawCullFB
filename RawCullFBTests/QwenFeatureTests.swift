import Foundation
@testable import RawCullFB
import Testing

@Suite("Qwen feature")
struct QwenFeatureTests {
    @Test
    func `Qwen manager validates a compatible Core AI bundle`() async throws {
        let bundle = try makeQwenBundle()
        defer { try? FileManager.default.removeItem(at: bundle) }

        let status = await QwenModelManager().validate(url: bundle)

        guard case let .available(url, modelName) = status else {
            Issue.record("Expected the Qwen model bundle to validate, got \(status)")
            return
        }
        #expect(url.standardizedFileURL == bundle.standardizedFileURL)
        #expect(modelName == "qwen3_4b_test")
    }

    @Test
    func `Qwen manager rejects a non-Qwen model`() async throws {
        let bundle = try makeQwenBundle(tokenizer: "meta-llama/Llama-3.2-3B")
        defer { try? FileManager.default.removeItem(at: bundle) }

        let status = await QwenModelManager().validate(url: bundle)

        guard case .invalid = status else {
            Issue.record("Expected the non-Qwen model bundle to be rejected, got \(status)")
            return
        }
    }

    private func makeQwenBundle(
        tokenizer: String = "Qwen/Qwen3-4B",
    ) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RawCullFBQwenTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("tokenizer", isDirectory: true),
            withIntermediateDirectories: true,
        )
        try Data().write(to: root.appendingPathComponent("qwen.aimodelc"))
        try Data("{}".utf8).write(to: root.appendingPathComponent("tokenizer/tokenizer.json"))
        try Data("{}".utf8).write(to: root.appendingPathComponent("tokenizer/tokenizer_config.json"))
        let metadata = """
            {
              "metadata_version": "0.2",
              "kind": "llm",
              "name": "qwen3_4b_test",
              "assets": { "main": "qwen.aimodelc" },
              "language": {
                "tokenizer": "\(tokenizer)",
                "vocab_size": 151936,
                "max_context_length": 40960,
                "embedded_tokenizer": true,
                "function_map": { "main": ["main"] }
              },
              "source": { "hf_model_id": "\(tokenizer)" }
            }
            """
        try Data(metadata.utf8).write(to: root.appendingPathComponent("metadata.json"))
        return root
    }
}
