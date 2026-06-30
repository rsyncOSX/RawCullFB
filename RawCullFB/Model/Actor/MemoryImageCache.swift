import AppKit
import Foundation

actor MemoryImageCache {
    static let shared = MemoryImageCache()

    private struct ThumbnailCacheKey: Hashable {
        let url: URL
        let maxPixelSize: Int
    }

    private var thumbnailCache: [ThumbnailCacheKey: CachedNSImage] = [:]
    private var thumbnailAccessOrder: [ThumbnailCacheKey] = []
    private var thumbnailCostLimit = BrowserSettings.defaultGridCacheSizeMB * 1024 * 1024
    private var thumbnailCost = 0

    private init() {}

    func apply(settings: BrowserSettings) {
        thumbnailCostLimit = max(0, settings.gridCacheSizeMB) * 1024 * 1024
        trimThumbnailCache()
    }

    func thumbnail(for url: URL, maxPixelSize: Int) -> NSImage? {
        let key = thumbnailCacheKey(for: url, maxPixelSize: maxPixelSize)
        guard let cached = thumbnailCache[key] else { return nil }
        markThumbnailAsRecentlyUsed(key)
        return cached.image
    }

    func storeThumbnail(_ image: NSImage, for url: URL, maxPixelSize: Int) {
        guard thumbnailCostLimit > 0 else { return }

        let key = thumbnailCacheKey(for: url, maxPixelSize: maxPixelSize)
        let cached = CachedNSImage(image: image)
        if let previous = thumbnailCache[key] {
            thumbnailCost -= previous.cost
        }
        thumbnailCache[key] = cached
        thumbnailCost += cached.cost
        markThumbnailAsRecentlyUsed(key)
        trimThumbnailCache()
    }

    func clear() {
        thumbnailCache.removeAll()
        thumbnailAccessOrder.removeAll()
        thumbnailCost = 0
    }

    private func markThumbnailAsRecentlyUsed(_ key: ThumbnailCacheKey) {
        thumbnailAccessOrder.removeAll { $0 == key }
        thumbnailAccessOrder.append(key)
    }

    private func trimThumbnailCache() {
        while thumbnailCost > thumbnailCostLimit {
            guard let oldestKey = thumbnailAccessOrder.first else { return }
            thumbnailAccessOrder.removeFirst()
            if let removed = thumbnailCache.removeValue(forKey: oldestKey) {
                thumbnailCost -= removed.cost
            }
        }
    }

    private func thumbnailCacheKey(for url: URL, maxPixelSize: Int) -> ThumbnailCacheKey {
        ThumbnailCacheKey(url: url, maxPixelSize: max(maxPixelSize, 1))
    }
}
