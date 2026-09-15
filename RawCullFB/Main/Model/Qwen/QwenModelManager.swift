import CoreAIQwenBackend
import CoreAILanguageModels
import CoreGraphics
import Foundation
import FoundationModels

nonisolated enum QwenModelStatus: Equatable, Sendable {
    case notConfigured
    case checking(URL)
    case available(url: URL, modelName: String)
    case missing(URL)
    case invalid(url: URL, reason: String)

    var isAvailable: Bool {
        if case .available = self {
            true
        } else {
            false
        }
    }
}

actor QwenModelManager {
    private var provider: CoreAIQwenProvider?
    private var model: CoreAIVisionLanguageModel?

    func validate(url: URL) -> QwenModelStatus {
        let standardizedURL = url.standardizedFileURL
        let capability = CoreAIQwenProvider.factory.capability(in: [standardizedURL])

        switch capability {
        case let .available(resource):
            do {
                let provider = try CoreAIQwenProvider.factory.makeProvider(from: resource)
                guard provider.configuration.modality == .vision else {
                    clear()
                    return .invalid(
                        url: resource.bundleURL,
                        reason: QwenModelError.visionModelRequired.localizedDescription,
                    )
                }
                self.provider = provider
                model = nil
                return .available(
                    url: resource.bundleURL,
                    modelName: provider.configuration.name,
                )
            } catch {
                clear()
                return .invalid(url: standardizedURL, reason: Self.message(for: error))
            }

        case .missing:
            clear()
            return .missing(standardizedURL)

        case let .invalid(url, reason):
            clear()
            return .invalid(url: url, reason: reason)
        }
    }

    func respond(to prompt: String, image: CGImage) async throws -> String {
        guard let provider else {
            throw QwenModelError.modelUnavailable
        }

        let model: CoreAIVisionLanguageModel
        if let loadedModel = self.model {
            model = loadedModel
        } else {
            let loadedModel = try await provider.makeVisionLanguageModel()
            self.model = loadedModel
            model = loadedModel
        }

        let session = LanguageModelSession(model: model)
        let response = try await session.respond(
            options: GenerationOptions(maximumResponseTokens: 512)
        ) {
            Attachment(image)
            prompt
        }
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func clear() {
        model = nil
        provider = nil
    }

    private static func message(for error: Error) -> String {
        let description = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return description.isEmpty ? String(reflecting: error) : description
    }
}

nonisolated enum QwenModelError: Error, LocalizedError, Sendable {
    case modelUnavailable
    case visionModelRequired
    case imageUnavailable
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .modelUnavailable:
            "Select and validate a Qwen model in AI Settings first."
        case .visionModelRequired:
            "The selected model is text-only. Select a Qwen vision-language bundle, such as Qwen3-VL-2B-Instruct."
        case .imageUnavailable:
            "The selected photo could not be decoded for Qwen."
        case .emptyResponse:
            "Qwen returned an empty response."
        }
    }
}
