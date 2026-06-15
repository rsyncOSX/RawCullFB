import AppKit
import Foundation

struct BrowserFileItem: Identifiable, Hashable, Sendable {
    let id: UUID
    let url: URL
    let name: String
    let byteCount: Int64
    let modifiedDate: Date?

    nonisolated init(url: URL, byteCount: Int64 = 0, modifiedDate: Date? = nil) {
        self.id = UUID()
        self.url = url
        self.name = url.lastPathComponent
        self.byteCount = byteCount
        self.modifiedDate = modifiedDate
    }
}

struct BrowserFolderItem: Identifiable, Hashable, Sendable {
    let id: URL
    let url: URL
    let name: String
    let supportedFileCount: Int

    nonisolated init(url: URL, supportedFileCount: Int = 0) {
        self.id = url
        self.url = url
        self.name = url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
        self.supportedFileCount = supportedFileCount
    }
}

enum BrowserDisplayMode: String, CaseIterable, Identifiable {
    case grid
    case loupe

    var id: String { rawValue }

    var title: String {
        switch self {
        case .grid: "Grid"
        case .loupe: "Loupe"
        }
    }
}

struct BrowserSettings: Codable, Sendable {
    var memoryCacheSizeMB = 8000
    var gridCacheSizeMB = 2000
    var thumbnailSizeGrid = 200
    var thumbnailSizePreview = 1616
    var thumbnailSizeFullSize = 8700

    enum CodingKeys: String, CodingKey {
        case memoryCacheSizeMB
        case gridCacheSizeMB
        case thumbnailSizeGrid
        case thumbnailSizePreview
        case thumbnailSizeFullSize
    }
}

final class CachedNSImage: NSObject, @unchecked Sendable {
    let image: NSImage
    nonisolated let cost: Int

    nonisolated init(image: NSImage) {
        self.image = image
        var totalCost = 0
        for representation in image.representations {
            totalCost += representation.pixelsWide * representation.pixelsHigh * 4
        }
        if totalCost == 0 {
            totalCost = Int(image.size.width * image.size.height * 4)
        }
        self.cost = Int(Double(totalCost) * 1.1)
        super.init()
    }
}

final class CachedCGImage: NSObject, @unchecked Sendable {
    let image: CGImage
    nonisolated let cost: Int

    nonisolated init(image: CGImage) {
        self.image = image
        self.cost = Int(Double(image.width * image.height * 4) * 1.1)
        super.init()
    }
}
