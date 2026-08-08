import CoreAICLIPBackend
import Foundation
import PhotoAIContracts

nonisolated enum CLIPModelStatus: Equatable, Sendable {
    case notConfigured
    case checking(URL)
    case available(url: URL, fingerprint: String, modelName: String)
    case missing(URL)
    case invalid(url: URL, reason: String)

    var isAvailable: Bool {
        if case .available = self { true } else { false }
    }
}

nonisolated struct CLIPModelLoad: Sendable {
    let status: CLIPModelStatus
    let provider: CoreAICLIPProvider?
}

actor CLIPModelManager {
    func load(url: URL) -> CLIPModelLoad {
        let standardizedURL = url.standardizedFileURL
        let capability = CoreAICLIPProvider.factory.capability(in: [standardizedURL])
        switch capability {
        case let .available(resource):
            do {
                let provider = try CoreAICLIPProvider.factory.makeProvider(from: resource)
                let configuration = provider.runtimeConfiguration
                let name = configuration.pretrained ?? configuration.architecture
                return CLIPModelLoad(
                    status: .available(
                        url: resource.bundleURL,
                        fingerprint: provider.backendDescriptor.modelFingerprint,
                        modelName: name,
                    ),
                    provider: provider,
                )
            } catch {
                return CLIPModelLoad(
                    status: .invalid(url: standardizedURL, reason: String(describing: error)),
                    provider: nil,
                )
            }

        case .missing:
            return CLIPModelLoad(status: .missing(standardizedURL), provider: nil)

        case let .invalid(url, reason):
            return CLIPModelLoad(status: .invalid(url: url, reason: reason), provider: nil)
        }
    }
}
