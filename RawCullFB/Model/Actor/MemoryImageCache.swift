import AppKit
import Foundation

actor MemoryImageCache {
    static let shared = MemoryImageCache()

    private var thumbnailCache: [URL: CachedNSImage] = [:]
    private var thumbnailAccessOrder: [URL] = []
    private var thumbnailCostLimit = BrowserSettings.defaultGridCacheSizeMB * 1024 * 1024
    private var thumbnailCost = 0
    private var extractedJPGCache: [URL: CachedCGImage] = [:]
    private var extractedJPGAccessOrder: [URL] = []
    private var extractedJPGCostLimit = BrowserSettings.defaultMemoryCacheSizeMB * 1024 * 1024
    private var extractedJPGCost = 0
    private var maxCachedExtractedJPGs = BrowserSettings.defaultMaxCachedExtractedJPGs

    private init() {}

    func apply(settings: BrowserSettings) {
        thumbnailCostLimit = max(0, settings.gridCacheSizeMB) * 1024 * 1024
        extractedJPGCostLimit = max(0, settings.memoryCacheSizeMB) * 1024 * 1024
        maxCachedExtractedJPGs = max(0, settings.maxCachedExtractedJPGs)
        trimThumbnailCache()
        trimExtractedJPGCache()
    }

    func thumbnail(for url: URL) -> NSImage? {
        guard let cached = thumbnailCache[url] else { return nil }
        markThumbnailAsRecentlyUsed(url)
        return cached.image
    }

    func extractedJPG(for url: URL) -> CGImage? {
        guard let cached = extractedJPGCache[url] else { return nil }
        markExtractedJPGAsRecentlyUsed(url)
        return cached.image
    }

    func storeThumbnail(_ image: NSImage, for url: URL) {
        guard thumbnailCostLimit > 0 else { return }

        let cached = CachedNSImage(image: image)
        if let previous = thumbnailCache[url] {
            thumbnailCost -= previous.cost
        }
        thumbnailCache[url] = cached
        thumbnailCost += cached.cost
        markThumbnailAsRecentlyUsed(url)
        trimThumbnailCache()
    }

    func storeExtractedJPG(_ image: CGImage, for url: URL) {
        guard maxCachedExtractedJPGs > 0, extractedJPGCostLimit > 0 else { return }

        let cached = CachedCGImage(image: image)
        if let previous = extractedJPGCache[url] {
            extractedJPGCost -= previous.cost
        }
        extractedJPGCache[url] = cached
        extractedJPGCost += cached.cost
        markExtractedJPGAsRecentlyUsed(url)
        trimExtractedJPGCache()
    }

    func clear() {
        thumbnailCache.removeAll()
        thumbnailAccessOrder.removeAll()
        thumbnailCost = 0
        extractedJPGCache.removeAll()
        extractedJPGAccessOrder.removeAll()
        extractedJPGCost = 0
    }

    private func markThumbnailAsRecentlyUsed(_ url: URL) {
        thumbnailAccessOrder.removeAll { $0 == url }
        thumbnailAccessOrder.append(url)
    }

    private func markExtractedJPGAsRecentlyUsed(_ url: URL) {
        extractedJPGAccessOrder.removeAll { $0 == url }
        extractedJPGAccessOrder.append(url)
    }

    private func trimThumbnailCache() {
        while thumbnailCost > thumbnailCostLimit {
            guard let oldestURL = thumbnailAccessOrder.first else { return }
            thumbnailAccessOrder.removeFirst()
            if let removed = thumbnailCache.removeValue(forKey: oldestURL) {
                thumbnailCost -= removed.cost
            }
        }
    }

    private func trimExtractedJPGCache() {
        while extractedJPGCache.count > maxCachedExtractedJPGs || extractedJPGCost > extractedJPGCostLimit {
            guard let oldestURL = extractedJPGAccessOrder.first else { return }
            extractedJPGAccessOrder.removeFirst()
            if let removed = extractedJPGCache.removeValue(forKey: oldestURL) {
                extractedJPGCost -= removed.cost
            }
        }
    }
}
