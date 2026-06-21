import Foundation

/// Bounded FIFO of recently-evicted NSURLs from the main `memoryCache`.
/// Backing storage is a fixed-size array used as a ring (O(1) insert) plus a
/// `Set` mirror for O(1) membership tests.
struct EvictedRing {
    nonisolated static let capacity = 2000

    private var buffer: [NSURL?]
    private var set: Set<NSURL>
    private var cursor: Int

    nonisolated init() {
        buffer = Array(repeating: nil, count: Self.capacity)
        set = Set(minimumCapacity: Self.capacity)
        cursor = 0
    }

    nonisolated mutating func note(_ url: NSURL) {
        if let old = buffer[cursor] {
            set.remove(old)
        }
        buffer[cursor] = url
        set.insert(url)
        cursor = (cursor + 1) % Self.capacity
    }

    nonisolated func contains(_ url: NSURL) -> Bool {
        set.contains(url)
    }

    nonisolated mutating func clear() {
        for i in 0 ..< buffer.count {
            buffer[i] = nil
        }
        set.removeAll(keepingCapacity: true)
        cursor = 0
    }
}
