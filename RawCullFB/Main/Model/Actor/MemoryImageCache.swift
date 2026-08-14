import AppKit
import Foundation

actor MemoryImageCache {
    static let shared = MemoryImageCache()

    private let thumbnailCache = NSCache<NSString, CachedNSImage>()

    private init() {
        thumbnailCache.totalCostLimit = BrowserSettings.defaultGridCacheSizeMB * 1024 * 1024
        thumbnailCache.countLimit = 3000
    }

    func apply(settings: BrowserSettings) {
        thumbnailCache.totalCostLimit = max(0, settings.gridCacheSizeMB) * 1024 * 1024
    }

    func thumbnail(for url: URL, maxPixelSize: Int) -> NSImage? {
        let key = thumbnailCacheKey(for: url, maxPixelSize: maxPixelSize)
        return thumbnailCache.object(forKey: key)?.image
    }

    func storeThumbnail(_ image: NSImage, for url: URL, maxPixelSize: Int) {
        let key = thumbnailCacheKey(for: url, maxPixelSize: maxPixelSize)
        let cached = CachedNSImage(image: image)
        thumbnailCache.setObject(cached, forKey: key, cost: cached.cost)
    }

    private func thumbnailCacheKey(for url: URL, maxPixelSize: Int) -> NSString {
        "\(url.standardized.path)|\(max(maxPixelSize, 1))" as NSString
    }
}
