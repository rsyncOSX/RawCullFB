import CoreAIQwenBackend
import Foundation
import FoundationModels
import PhotoAIContracts
import Testing

@Suite("Qwen backend")
struct QwenBackendTests {
    @Test("Qwen 3 4B dynamic bundle metadata is accepted")
    func acceptsQwenBundle() throws {
        let bundle = try makeBundle()
        defer { try? FileManager.default.removeItem(at: bundle) }

        let provider = try CoreAIQwenProvider(modelBundleURL: bundle)

        #expect(provider.modelIdentity.family == "qwen")
        #expect(provider.configuration.name == "qwen3_4b_4bit_weights_8bit_kv_cache_dynamic")
        #expect(provider.configuration.tokenizerIdentifier == "Qwen/Qwen3-4B")
        #expect(provider.configuration.vocabularySize == 151_936)
        #expect(provider.configuration.maximumContextLength == 40_960)
        #expect(provider.configuration.hasEmbeddedTokenizer)
        #expect(provider.configuration.compression == "4bit_weights_8bit_kv_cache")
        #expect(provider.configuration.assetName == "qwen.aimodelc")
        #expect(provider.configuration.modality == .text)
    }

    @Test("Qwen vision-language bundle metadata is accepted")
    func acceptsQwenVisionBundle() throws {
        let bundle = try makeBundle(kind: "vlm")
        defer { try? FileManager.default.removeItem(at: bundle) }

        let provider = try CoreAIQwenProvider(modelBundleURL: bundle)

        #expect(provider.configuration.modality == .vision)
    }

    @Test("Non-Qwen language bundles are rejected")
    func rejectsOtherLanguageModel() throws {
        let bundle = try makeBundle(tokenizer: "meta-llama/Llama-3.2-3B")
        defer { try? FileManager.default.removeItem(at: bundle) }

        #expect(throws: QwenProviderError.self) {
            _ = try CoreAIQwenProvider(modelBundleURL: bundle)
        }
    }

    @Test("Supplied Qwen Core AI bundle generates a response when configured")
    func suppliedBundleInitializes() async throws {
        guard let path = ProcessInfo.processInfo.environment["QWEN_COREAI_BUNDLE"] else { return }
        let provider = try CoreAIQwenProvider(modelBundleURL: URL(fileURLWithPath: path))
        let model = try await provider.makeLanguageModel()
        #expect(model.estimatedSizeOnDiskBytes != nil)
        let session = LanguageModelSession(model: model)
        _ = try await session.respond(
            to: "Reply with OK. /no_think",
            options: GenerationOptions(maximumResponseTokens: 16)
        ).content
        model.unload()
    }

    private func makeBundle(
        tokenizer: String = "Qwen/Qwen3-4B",
        kind: String = "llm"
    ) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoAIKitQwenTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("tokenizer", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data().write(to: root.appendingPathComponent("qwen.aimodelc"))
        if kind == "vlm" {
            try Data().write(to: root.appendingPathComponent("embedding.aimodelc"))
            try Data().write(to: root.appendingPathComponent("vision.aimodelc"))
        }
        try Data("{}".utf8).write(to: root.appendingPathComponent("tokenizer/tokenizer.json"))
        try Data("{}".utf8).write(to: root.appendingPathComponent("tokenizer/tokenizer_config.json"))
        let metadata = """
            {
              "metadata_version": "0.2",
              "kind": "\(kind)",
              "name": "qwen3_4b_4bit_weights_8bit_kv_cache_dynamic",
              "assets": {
                "main": "qwen.aimodelc",
                "embedding": "embedding.aimodelc",
                "vision": "vision.aimodelc"
              },
              "vision": {
                "image_size": 448,
                "patch_size": 14,
                "image_token_count": 256,
                "image_token_id": 151655
              },
              "language": {
                "tokenizer": "\(tokenizer)",
                "vocab_size": 151936,
                "max_context_length": 40960,
                "embedded_tokenizer": true,
                "function_map": { "main": ["main"] }
              },
              "source": { "hf_model_id": "\(tokenizer)" },
              "compression": "4bit_weights_8bit_kv_cache"
            }
            """
        try Data(metadata.utf8).write(to: root.appendingPathComponent("metadata.json"))
        return root
    }
}
