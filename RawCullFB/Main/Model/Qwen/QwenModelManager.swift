import CoreAIQwenBackend
import CoreAILanguageModels
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
    private var model: CoreAILanguageModel?

    func validate(url: URL) -> QwenModelStatus {
        let standardizedURL = url.standardizedFileURL
        let capability = CoreAIQwenProvider.factory.capability(in: [standardizedURL])

        switch capability {
        case let .available(resource):
            do {
                let provider = try CoreAIQwenProvider.factory.makeProvider(from: resource)
                model?.unload()
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

    func respond(to prompt: String) async throws -> String {
        guard let provider else {
            throw QwenModelError.modelUnavailable
        }

        let model: CoreAILanguageModel
        if let loadedModel = self.model {
            model = loadedModel
        } else {
            let loadedModel = try await provider.makeLanguageModel()
            self.model = loadedModel
            model = loadedModel
        }

        let session = LanguageModelSession(model: model)
        let response = try await session.respond(
            to: prompt,
            options: GenerationOptions(maximumResponseTokens: 512),
        )
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func clear() {
        model?.unload()
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
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .modelUnavailable:
            "Select and validate a Qwen model in AI Settings first."
        case .emptyResponse:
            "Qwen returned an empty response."
        }
    }
}
