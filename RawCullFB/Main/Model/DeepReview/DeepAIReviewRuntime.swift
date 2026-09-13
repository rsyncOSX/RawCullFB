import CoreAISAM3Backend
import CoreGraphics
import Foundation
import PhotoAIContracts
import PhotoAIStorage
import PhotoAIWorkflows

@MainActor
final class DeepAIReviewRuntime {
    private let memoryStore = SubjectMaskMemoryStore()
    private let diskStore: SubjectMaskDiskStore?
    private let inputMaxSide = 4320
    private let deepReviewMaximumPixelSize = 2048
    private var subjectMaskStores: [any SubjectMaskStoring]
    private var subjectMaskRepository: SubjectMaskRepository
    private var subjectMaskSelector: SubjectMaskSelector
    private var activeModelIdentity: ModelIdentity?

    init() {
        let maskDirectory = Self.defaultMaskDirectory()
        let diskStore = try? SubjectMaskDiskStore(cacheDirectory: maskDirectory)
        self.diskStore = diskStore
        self.subjectMaskStores = [memoryStore] + (diskStore.map { [$0] } ?? [])
        let provider = UnavailableSegmentationProvider()
        let configuration = SubjectMaskRepositoryConfiguration(
            defaultPrompt: .subject,
            modelIdentity: provider.modelIdentity,
            inputMaxSide: inputMaxSide,
        )
        let repository = SubjectMaskRepository(
            configuration: configuration,
            stores: subjectMaskStores,
        )
        self.subjectMaskRepository = repository
        let segmentation = SegmentationService(
            provider: provider,
            stores: subjectMaskStores,
            maxSide: inputMaxSide,
        )
        self.subjectMaskSelector = SubjectMaskSelector(
            repository: repository,
            segmentationService: segmentation,
        )
    }

    func activateSAM3(
        at url: URL?,
        controller: DeepAIReviewController,
    ) async {
        guard let url else {
            installUnavailable(
                controller: controller,
                availability: .missing(expectedLocations: [Self.defaultSAM3Directory()]),
            )
            return
        }

        let standardizedURL = url.standardizedFileURL
        let capability = CoreAISAM3Provider.factory.capability(in: [standardizedURL])
        switch capability {
        case let .available(resource):
            do {
                let provider = try CoreAISAM3Provider.factory.makeProvider(from: resource)
                install(
                    provider: provider,
                    controller: controller,
                    availability: .available(location: resource.bundleURL),
                )
            } catch {
                installUnavailable(
                    controller: controller,
                    availability: .invalid(
                        location: standardizedURL,
                        reason: String(describing: error),
                    ),
                )
            }

        case .missing:
            installUnavailable(
                controller: controller,
                availability: .missing(expectedLocations: [standardizedURL]),
            )

        case let .invalid(url, reason):
            installUnavailable(
                controller: controller,
                availability: .invalid(location: url, reason: reason),
            )
        }
    }

    private func install(
        provider: any SubjectSegmenting,
        controller: DeepAIReviewController,
        availability: RawCullAICapabilityStatus,
    ) {
        if activeModelIdentity != provider.modelIdentity {
            activeModelIdentity = provider.modelIdentity
            let configuration = SubjectMaskRepositoryConfiguration(
                defaultPrompt: .subject,
                modelIdentity: provider.modelIdentity,
                inputMaxSide: inputMaxSide,
            )
            let repository = SubjectMaskRepository(
                configuration: configuration,
                stores: subjectMaskStores,
            )
            let segmentation = SegmentationService(
                provider: provider,
                stores: subjectMaskStores,
                maxSide: inputMaxSide,
            )
            subjectMaskRepository = repository
            subjectMaskSelector = SubjectMaskSelector(
                repository: repository,
                segmentationService: segmentation,
            )
        }

        controller.install(
            service: RawCullDeepAIReviewPipeline(
                selector: subjectMaskSelector,
                maximumPixelSize: min(inputMaxSide, deepReviewMaximumPixelSize),
            ),
            maskLoader: diskStore.map {
                DeepAIReviewDiskMaskLoader(
                    repository: subjectMaskRepository,
                    diskStore: $0,
                )
            },
            availability: availability,
        )
    }

    private func installUnavailable(
        controller: DeepAIReviewController,
        availability: RawCullAICapabilityStatus,
    ) {
        activeModelIdentity = nil
        controller.install(
            service: nil,
            maskLoader: nil,
            availability: availability,
        )
    }

    private static func defaultSAM3Directory() -> URL {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
        )[0]
        .appendingPathComponent("RawCullFB", isDirectory: true)
        .appendingPathComponent("Models", isDirectory: true)
        .appendingPathComponent("SAM3", isDirectory: true)
    }

    private static func defaultMaskDirectory() -> URL {
        FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask,
        )[0]
        .appendingPathComponent("RawCullFB", isDirectory: true)
        // Earlier builds decoded the full RAW preview despite requesting a
        // bounded analysis image, so their cached masks can be tens of
        // megapixels. Use a new cache generation rather than loading those
        // oversized artifacts into the subject-outline UI.
        .appendingPathComponent("SubjectMasks-v2", isDirectory: true)
    }
}

private struct UnavailableSegmentationProvider: SubjectSegmenting {
    let modelIdentity = ModelIdentity(
        family: "sam3",
        name: "unavailable",
        assetName: "",
        cacheIdentifier: "coreai-sam3-local",
    )

    func segment(_: SubjectSegmentationRequest) async throws -> SubjectSegmentationResult {
        throw SubjectSegmentationError.providerFailure(
            "The selected segmentation model resources are not installed.",
        )
    }
}

nonisolated struct DeepAIReviewDiskMaskLoader: DeepAIReviewMaskLoading, Sendable {
    let repository: SubjectMaskRepository
    let diskStore: SubjectMaskDiskStore

    func mask(
        for source: AIImageSource,
        prompt: SubjectSegmentationPrompt,
    ) async -> CGImage? {
        let key = await repository.storageKey(for: source, prompt: prompt)
        return await diskStore.load(for: key)?.mask
    }
}
