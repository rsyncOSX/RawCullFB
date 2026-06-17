//
//  SharedMemoryCache.swift
//  RawCull
//
//  Created by Thomas Evensen on 11/02/2026.
//

import AppKit
import Dispatch
import Foundation
import os

// import OSLog

/// A thread-safe singleton wrapper around the shared NSCache.
/// We use 'actor' to safely manage state (configuration, settings) across async contexts.
/// We use 'nonisolated(unsafe)' for the NSCache because NSCache is internally thread-safe,
/// allowing us to access it synchronously without actor hops.
actor SharedMemoryCache {
    
    private init() {}
    
    /// Only using the memory pressure warning
    private var fileHandlers: FileHandlers?
    
    nonisolated static let shared = SharedMemoryCache()

    // Cache statistics for monitoring (Actor specific, not shared)
    private var cacheMemory = 0
    private var cacheDisk = 0
    /// Note: cacheEvictions is now tracked by CacheDelegate and read from there
    private let _gridCost = OSAllocatedUnfairLock(initialState: 0)
    private let _gridCount = OSAllocatedUnfairLock(initialState: 0)
    /// Manual count/cost tracking for the main `memoryCache`, mirroring the
    /// grid-cache counters above. NSCache does not expose item count or current
    /// total cost via its public API, so we maintain these alongside every
    /// `setObject` / `removeAllObjects` / eviction-delegate call. Surfaced via
    /// `getMemoryCacheCount()` / `getMemoryCacheCurrentCost()` for the Memory
    /// Diagnostics console (and any future cache-monitor UI).
    private let _memCost = OSAllocatedUnfairLock(initialState: 0)
    private let _memCount = OSAllocatedUnfairLock(initialState: 0)

    // MARK: - Boomerang-miss diagnostics

    //
    // Three demand-traffic counters and a bounded FIFO of recently-evicted
    // URLs from `memoryCache`, used by the Memory Diagnostics view to compute
    // a true RAM hit rate (denominator = all demand requests, including cold
    // extractions) and detect scan-vs-UI cache pollution.
    //
    //   _cacheCold:        successful branch C extractions in RequestThumbnail
    //                      (not in RAM, not on disk → extracted from ARW source)
    //   _demandRequests:   total calls into RequestThumbnail.resolveImage
    //   _boomerangMisses:  branch B disk hits whose URL was just evicted from
    //                      RAM (a re-request the cache was supposed to serve)
    //
    // The ring is capacity-bounded (~2000 keys, ≈2× current peak _memCount) so
    // the boomerang signal reflects recent evictions only. Cleared on
    // `clearCaches()` and on `.critical` memory pressure to avoid spurious
    // hits after a wholesale flush.
    private let _cacheCold = OSAllocatedUnfairLock(initialState: 0)
    private let _demandRequests = OSAllocatedUnfairLock(initialState: 0)
    private let _boomerangMisses = OSAllocatedUnfairLock(initialState: 0)
    private let _evictedRing = OSAllocatedUnfairLock(initialState: EvictedRing())

    // MARK: - Pressure event counters

    //
    // Cumulative counts of memory-pressure transitions handled by
    // `handleMemoryPressureEvent`. The 5-second diagnostics sampler can miss
    // a `.warning → .normal` flicker — these counters can't, so a delta
    // between TSV samples reveals events even when `pressure` reads "Normal"
    // at both endpoints. `getLiveTotalCostLimit()` reads the NSCache's live
    // cost cap so transient shrinks (the warning case multiplies the cap by
    // 0.6 and waits for a `.normal` to restore it) become visible too.
    private let _pressureWarnings = OSAllocatedUnfairLock(initialState: 0)
    private let _pressureCriticals = OSAllocatedUnfairLock(initialState: 0)
    private let _pressureNormals = OSAllocatedUnfairLock(initialState: 0)

    // For Cache monitor

    // MARK: - Memory pressure level

    /// The kernel-reported memory pressure level.
    enum MemoryPressureLevel {
        case normal, warning, critical

        var label: String {
            switch self {
            case .normal: "Normal"
            case .warning: "Warning"
            case .critical: "Critical"
            }
        }

        var systemImage: String {
            switch self {
            case .normal: "checkmark.circle.fill"
            case .warning: "exclamationmark.triangle.fill"
            case .critical: "xmark.octagon.fill"
            }
        }
    }

    /// Synchronously readable because every read and write goes through this lock.
    private let _currentPressureLevel = OSAllocatedUnfairLock(initialState: MemoryPressureLevel.normal)

    /// Exposes the latest pressure level without an actor hop for UI sampling and diagnostics.
    nonisolated var currentPressureLevel: MemoryPressureLevel {
        _currentPressureLevel.withLock { $0 }
    }

    private func setCurrentPressureLevel(_ level: MemoryPressureLevel) {
        _currentPressureLevel.withLock { $0 = level }
    }

    /// Bytes per pixel used by `CachedThumbnail` to compute NSCache cost.
    /// Fixed at 4 (RGBA) — NSImage representations are always sRGB RGBA in
    /// this app, so the cost calculation has no reason to vary at runtime.
    /// `nonisolated let` lets call sites read it without `await`.
    nonisolated let costPerPixel: Int = 4

    // MARK: - Isolated State (Protected by Actor)

    private var memoryPressureSource: DispatchSourceMemoryPressure?

    private var setupTask: Task<Void, Never>?


    // MARK: - Memory Pressure Monitoring

    private func startMemoryPressureMonitoring() {
        // Avoid duplicate sources
        if memoryPressureSource != nil {
            return
        }

        // Logger.process.debugMessageOnly( "SharedMemoryCache: startMemoryPressureMonitoring()",)

        let source = DispatchSource.makeMemoryPressureSource(eventMask: .all, queue: .global(qos: .utility))

        source.setEventHandler { [weak self] in
            guard let self else { return }
            Task {
                await self.handleMemoryPressureEvent()
            }
        }

        source.setCancelHandler { [weak self] in
            guard let self else { return }
            Task {
                await self.logMemoryPressure("Memory pressure monitoring cancelled")
            }
        }

        source.resume()
        memoryPressureSource = source
        // Logger.process.debugMessageOnly("SharedMemoryCache: Memory pressure monitoring started")
    }

    /// Responds to kernel-reported memory-pressure transitions:
    ///   • `.normal`    → reload the full `CacheConfig` from settings (restore caps).
    ///   • `.warning`   → shrink both caches in place: `newCap = currentCap · 0.6`.
    ///                    Existing entries are retained until NSCache evicts under
    ///                    the lower cap, avoiding a full cache flush.
    ///   • `.critical`  → `removeAllObjects()` on both caches and floor the main
    ///                    cache at 50 MiB (50 · 1024 · 1024 bytes) until recovery.
    private func handleMemoryPressureEvent() {
        guard let source = memoryPressureSource else { return }

        let pressureLevel = source.data

        switch pressureLevel {
        case .normal:
            setCurrentPressureLevel(.normal)
            _pressureNormals.withLock { $0 += 1 }
            logMemoryPressure("Normal memory pressure")
            Task {
                await fileHandlers?.memorypressurewarning(false)
            }

        case .warning:
            setCurrentPressureLevel(.warning)
            _pressureWarnings.withLock { $0 += 1 }
            logMemoryPressure("Warning: Memory pressure detected, reducing cache to 60%")
            
            Task {
                await fileHandlers?.memorypressurewarning(true)
            }

        case .critical:
            setCurrentPressureLevel(.critical)
            _pressureCriticals.withLock { $0 += 1 }
            logMemoryPressure("CRITICAL: Memory pressure critical, clearing cache")
            _memCost.withLock { $0 = 0 }
            _memCount.withLock { $0 = 0 }
            _gridCost.withLock { $0 = 0 }
            _gridCount.withLock { $0 = 0 }
            // Wholesale flush invalidates per-URL eviction tracking; otherwise
            // every subsequent disk-fallback would falsely register as a
            // boomerang. Demand counters intentionally NOT reset.
            _evictedRing.withLock { $0.clear() }
            Task {
                await fileHandlers?.memorypressurewarning(true)
            }

        default:
            logMemoryPressure("Unknown memory pressure event: \(pressureLevel.rawValue)")
        }
    }

    private func logMemoryPressure(_: String) {
        // Logger.process.debugMessageOnly("SharedMemoryCache: \(message)")
    }

   
    nonisolated func getMemoryCacheCurrentCost() -> Int {
        _memCost.withLock { $0 }
    }

    nonisolated func getMemoryCacheCount() -> Int {
        _memCount.withLock { $0 }
    }

    nonisolated func memEntryEvicted(cost: Int) {
        _memCost.withLock { $0 = max(0, $0 - cost) }
        _memCount.withLock { $0 = max(0, $0 - 1) }
    }

    

    nonisolated func getGridCacheCurrentCost() -> Int {
        _gridCost.withLock { $0 }
    }

    nonisolated func getGridCacheCount() -> Int {
        _gridCount.withLock { $0 }
    }

    nonisolated func gridEntryEvicted(cost: Int) {
        _gridCost.withLock { $0 = max(0, $0 - cost) }
        _gridCount.withLock { $0 = max(0, $0 - 1) }
    }

    // MARK: - Boomerang-miss helpers

    nonisolated func noteEviction(url: NSURL) {
        _evictedRing.withLock { $0.note(url) }
    }

    nonisolated func wasRecentlyEvicted(url: NSURL) -> Bool {
        _evictedRing.withLock { $0.contains(url) }
    }

    nonisolated func incrementColdExtract() {
        _cacheCold.withLock { $0 += 1 }
    }

    nonisolated func incrementDemandRequest() {
        _demandRequests.withLock { $0 += 1 }
    }

    nonisolated func incrementBoomerangMiss() {
        _boomerangMisses.withLock { $0 += 1 }
    }

    nonisolated func getColdExtractCount() -> Int {
        _cacheCold.withLock { $0 }
    }

    nonisolated func getDemandRequestCount() -> Int {
        _demandRequests.withLock { $0 }
    }

    nonisolated func getBoomerangMissCount() -> Int {
        _boomerangMisses.withLock { $0 }
    }

    // MARK: - Pressure event getters

    nonisolated func getPressureWarningCount() -> Int {
        _pressureWarnings.withLock { $0 }
    }

    nonisolated func getPressureCriticalCount() -> Int {
        _pressureCriticals.withLock { $0 }
    }

    
   


    func updateCacheMemory() async {
        cacheMemory += 1
        // Logger.process.debugThreadOnly("SharedMemoryCache: updateCacheMemory() - found in RAM Cache (hits: \(cacheMemory))")
    }

    func updateCacheDisk() async {
        cacheDisk += 1
        // Logger.process.debugThreadOnly("SharedMemoryCache: updateCacheDisk() - found in Disk Cache (hits: \(cacheDisk))")
    }
}

/// Bounded FIFO of recently-evicted NSURLs from the main `memoryCache`.
/// Backing storage is a fixed-size array used as a ring (O(1) insert) plus a
/// `Set` mirror for O(1) membership tests. Always accessed under
/// `SharedMemoryCache._evictedRing`'s unfair lock — the struct itself
/// performs no synchronization.
///
/// All members are `nonisolated` because the project sets
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`; this struct is constructed
/// and mutated from the actor's own isolation domain (and from
/// `CacheDelegate`'s nonisolated callback), neither of which is MainActor.
private struct EvictedRing {
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


struct CreateFileHandlers {
    func createFileHandlers(
        memorypressurewarning: @escaping @MainActor @Sendable (Bool) -> Void
    ) -> FileHandlers {
        FileHandlers(
            memorypressurewarning: memorypressurewarning
        )
    }
}

struct FileHandlers {
    let memorypressurewarning: @MainActor @Sendable (Bool) -> Void
}
