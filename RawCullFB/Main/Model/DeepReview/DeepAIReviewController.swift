import CoreGraphics
import Foundation
import Observation
import OSLog

nonisolated enum DeepAIReviewPresentationState: Equatable, Sendable {
    case checking(expectedLocations: [URL])
    case unavailable(reason: String)
    case ready
    case preparing(groupID: Int, totalCount: Int)
    case running(DeepAIReviewProgress)
    case completing(groupID: Int)
    case cancelled(groupID: Int)
    case failed(groupID: Int?, failure: DeepAIReviewFailure)
    case completed(DeepAIReviewResult)
}

@Observable @MainActor
final class DeepAIReviewController {
    @ObservationIgnored private let feature: DeepAIReviewFeature

    init(feature: DeepAIReviewFeature = DeepAIReviewFeature()) {
        self.feature = feature
    }

    var preset: DeepAIReviewPreset {
        get { feature.preset }
        set { feature.preset = newValue }
    }

    var scope: DeepAIReviewScope {
        get { feature.scope }
        set { feature.scope = newValue }
    }

    var isRunning: Bool {
        feature.isRunning
    }

    var isActionUnavailable: Bool {
        !feature.availability.isAvailable || feature.isRunning
    }

    func result(for signature: BurstGroupSignature) -> DeepAIReviewResult? {
        feature.result(for: signature)
    }

    func maskCandidate(for fileID: UUID) -> DeepAIReviewCandidate? {
        feature.maskCandidate(for: fileID)
    }

    func mask(
        for candidate: DeepAIReviewCandidate,
        in files: [BrowserFileItem],
    ) async -> CGImage? {
        guard let file = files.first(where: { $0.id == candidate.fileID })
        else { return nil }
        return await feature.mask(for: candidate, fileURL: file.url)
    }

    func presentationState(
        groupID: Int,
        groupSignature: BurstGroupSignature,
    ) -> DeepAIReviewPresentationState {
        if let result = feature.result(for: groupSignature) {
            return .completed(result)
        }
        if let activeState = activePresentationState(groupID: groupID) {
            return activeState
        }
        return availabilityPresentationState
    }

    private func activePresentationState(
        groupID: Int,
    ) -> DeepAIReviewPresentationState? {
        switch feature.state {
        case let .preparing(activeGroupID, totalCount) where activeGroupID == groupID:
            .preparing(groupID: activeGroupID, totalCount: totalCount)
        case let .running(progress) where progress.groupID == groupID:
            .running(progress)
        case let .completing(activeGroupID) where activeGroupID == groupID:
            .completing(groupID: activeGroupID)
        case let .cancelled(activeGroupID) where activeGroupID == groupID:
            .cancelled(groupID: activeGroupID)
        case let .failed(activeGroupID, failure)
            where activeGroupID == nil || activeGroupID == groupID:
            .failed(groupID: activeGroupID, failure: failure)
        case .idle, .preparing, .running, .completing, .cancelled, .failed, .completed:
            nil
        }
    }

    private var availabilityPresentationState: DeepAIReviewPresentationState {
        switch feature.availability {
        case let .checking(expectedLocations):
            return .checking(expectedLocations: expectedLocations)
        case .available:
            return .ready
        case let .missing(expectedLocations):
            let reason = expectedLocations.first.map {
                "Install the selected segmentation model at \($0.path)."
            } ?? "Install the selected segmentation model."
            return .unavailable(reason: reason)
        case let .invalid(location, reason):
            let message = location.map {
                "The selected segmentation model at \($0.path) is invalid: \(reason)"
            } ?? "The selected segmentation model is invalid: \(reason)"
            return .unavailable(reason: message)
        case let .unavailable(reason):
            return .unavailable(reason: reason)
        }
    }

    func install(
        service: (any DeepAIReviewServicing)?,
        maskLoader: (any DeepAIReviewMaskLoading)?,
        availability: RawCullAICapabilityStatus,
    ) {
        feature.install(
            service: service,
            maskLoader: maskLoader,
            availability: availability,
        )
    }

    func start(
        groupID: Int,
        groupSignature: BurstGroupSignature,
        candidates: [DeepAIReviewInputCandidate],
    ) async {
        let request = DeepAIReviewRequest(
            groupID: groupID,
            groupSignature: groupSignature,
            candidates: candidates,
            preset: preset,
            scope: scope,
            scoringSource: .embeddedPreview,
        )
        await feature.start(request)
    }

    func cancel() {
        feature.cancel()
    }

    func reset() {
        feature.reset()
    }
}
