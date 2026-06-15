import AppKit
import Foundation

actor MemoryImageCache {
    static let shared = MemoryImageCache()

    private nonisolated(unsafe) let thumbnailCache = NSCache<NSURL, CachedNSImage>()
    private var extractedJPGCache: [URL: CachedCGImage] = [:]
    private var extractedJPGAccessOrder: [URL] = []
    private var extractedJPGCostLimit = 8000 * 1024 * 1024
    private var extractedJPGCost = 0
    private var maxCachedExtractedJPGs = 12

    private init() {}

    func apply(settings: BrowserSettings) {
        thumbnailCache.totalCostLimit = settings.gridCacheSizeMB * 1024 * 1024
        thumbnailCache.countLimit = 10000
        extractedJPGCostLimit = max(0, settings.memoryCacheSizeMB) * 1024 * 1024
        maxCachedExtractedJPGs = max(0, settings.maxCachedExtractedJPGs)
        trimExtractedJPGCache()
    }

    nonisolated func thumbnail(for url: URL) -> NSImage? {
        thumbnailCache.object(forKey: url as NSURL)?.image
    }

    func extractedJPG(for url: URL) -> CGImage? {
        guard let cached = extractedJPGCache[url] else { return nil }
        markExtractedJPGAsRecentlyUsed(url)
        return cached.image
    }

    nonisolated func storeThumbnail(_ image: NSImage, for url: URL) {
        let cached = CachedNSImage(image: image)
        thumbnailCache.setObject(cached, forKey: url as NSURL, cost: cached.cost)
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
        thumbnailCache.removeAllObjects()
        extractedJPGCache.removeAll()
        extractedJPGAccessOrder.removeAll()
        extractedJPGCost = 0
    }

    private func markExtractedJPGAsRecentlyUsed(_ url: URL) {
        extractedJPGAccessOrder.removeAll { $0 == url }
        extractedJPGAccessOrder.append(url)
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
