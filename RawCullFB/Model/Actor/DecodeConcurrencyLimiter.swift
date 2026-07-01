import Foundation

/// A shared, rate-limited slot allocator used to bound how many expensive
/// image decode operations (RAW demosaic, full-size JPEG extraction, etc.)
/// can run concurrently. Without a cap, rapid navigation/scrolling can spawn
/// many simultaneous decodes that each allocate large bitmaps, causing sharp
/// memory spikes.
actor DecodeConcurrencyLimiter {
    private enum SlotAcquisition {
        case granted
        case cancelled
    }

    private let maxConcurrent: Int
    private var activeTasks = 0
    private var pendingContinuations: [(id: UUID, continuation: CheckedContinuation<SlotAcquisition, Never>)] = []

    init(maxConcurrent: Int) {
        self.maxConcurrent = max(1, maxConcurrent)
    }

    /// Runs `work` once a concurrency slot is available, releasing the slot
    /// when `work` completes (or is cancelled). Returns `nil` if the calling
    /// task is cancelled before a slot is granted, or if `work` itself
    /// returns `nil`.
    func run<T>(_ work: @Sendable () async -> T?) async -> T? {
        guard await acquireSlot() == .granted else { return nil }
        defer { releaseSlot() }
        guard !Task.isCancelled else { return nil }
        return await work()
    }

    private func acquireSlot() async -> SlotAcquisition {
        guard !Task.isCancelled else { return .cancelled }

        if activeTasks < maxConcurrent {
            activeTasks += 1
            return .granted
        }

        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(returning: .cancelled)
                    return
                }
                pendingContinuations.append((id: id, continuation: continuation))
            }
        } onCancel: {
            Task {
                await self.removeAndResumePendingContinuation(id: id)
            }
        }
    }

    private func removeAndResumePendingContinuation(id: UUID) {
        if let index = pendingContinuations.firstIndex(where: { $0.id == id }) {
            let entry = pendingContinuations.remove(at: index)
            entry.continuation.resume(returning: .cancelled)
        }
    }

    private func releaseSlot() {
        if let next = pendingContinuations.first {
            pendingContinuations.removeFirst()
            // Transfer this real slot directly to the next waiter. Keeping
            // activeTasks unchanged prevents a new caller from over-admitting
            // before the waiter resumes.
            next.continuation.resume(returning: .granted)
            return
        }

        activeTasks = max(activeTasks - 1, 0)
    }
}
