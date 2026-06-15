import AppKit
import Foundation

actor MemoryImageCache {
    static let shared = MemoryImageCache()

    private nonisolated(unsafe) let thumbnailCache = NSCache<NSURL, CachedNSImage>()
    private nonisolated(unsafe) let extractedJPGCache = NSCache<NSURL, CachedCGImage>()

    private init() {}

    func apply(settings: BrowserSettings) {
        thumbnailCache.totalCostLimit = settings.gridCacheSizeMB * 1024 * 1024
        thumbnailCache.countLimit = 10000
        extractedJPGCache.totalCostLimit = settings.memoryCacheSizeMB * 1024 * 1024
        extractedJPGCache.countLimit = 2000
    }

    nonisolated func thumbnail(for url: URL) -> NSImage? {
        thumbnailCache.object(forKey: url as NSURL)?.image
    }

    nonisolated func extractedJPG(for url: URL) -> CGImage? {
        extractedJPGCache.object(forKey: url as NSURL)?.image
    }

    nonisolated func storeThumbnail(_ image: NSImage, for url: URL) {
        let cached = CachedNSImage(image: image)
        thumbnailCache.setObject(cached, forKey: url as NSURL, cost: cached.cost)
    }

    nonisolated func storeExtractedJPG(_ image: CGImage, for url: URL) {
        let cached = CachedCGImage(image: image)
        extractedJPGCache.setObject(cached, forKey: url as NSURL, cost: cached.cost)
    }

    nonisolated func clear() {
        thumbnailCache.removeAllObjects()
        extractedJPGCache.removeAllObjects()
    }
}
