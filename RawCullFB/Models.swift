import AppKit
import Foundation

struct BrowserFileItem: Identifiable, Hashable {
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

struct BrowserFolderItem: Identifiable, Hashable {
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

struct RememberedCatalog: Codable, Identifiable {
    var id: String {
        path
    }

    let name: String
    let path: String
    let lastBrowsedAt: Date
    let bookmarkData: Data
}

struct CopyProgress: Equatable {
    var completedCount = 0
    var totalCount = 0

    var isActive: Bool {
        totalCount > 0 && completedCount < totalCount
    }
}

struct CopyFailure: Identifiable, Equatable {
    let id = UUID()
    let message: String
}

struct BrowserSettings: Codable {
    nonisolated static let defaultMemoryCacheSizeMB = 768
    nonisolated static let defaultGridCacheSizeMB = 256
    nonisolated static let defaultMaxCachedExtractedJPGs = 4

    var memoryCacheSizeMB = defaultMemoryCacheSizeMB
    var gridCacheSizeMB = defaultGridCacheSizeMB
    var maxCachedExtractedJPGs = defaultMaxCachedExtractedJPGs
    var thumbnailSizeGrid = 200
    var thumbnailSizePreview = 1616
    var thumbnailSizeFullSize = 8700

    enum CodingKeys: String, CodingKey {
        case memoryCacheSizeMB
        case gridCacheSizeMB
        case maxCachedExtractedJPGs
        case thumbnailSizeGrid
        case thumbnailSizePreview
        case thumbnailSizeFullSize
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        memoryCacheSizeMB = try min(
            container.decodeIfPresent(Int.self, forKey: .memoryCacheSizeMB) ?? memoryCacheSizeMB,
            Self.defaultMemoryCacheSizeMB,
        )
        gridCacheSizeMB = try min(
            container.decodeIfPresent(Int.self, forKey: .gridCacheSizeMB) ?? gridCacheSizeMB,
            Self.defaultGridCacheSizeMB,
        )
        maxCachedExtractedJPGs = try min(
            container.decodeIfPresent(Int.self, forKey: .maxCachedExtractedJPGs) ?? maxCachedExtractedJPGs,
            Self.defaultMaxCachedExtractedJPGs,
        )
        thumbnailSizeGrid = try container.decodeIfPresent(Int.self, forKey: .thumbnailSizeGrid) ?? thumbnailSizeGrid
        thumbnailSizePreview = try container.decodeIfPresent(Int.self, forKey: .thumbnailSizePreview) ?? thumbnailSizePreview
        thumbnailSizeFullSize = try container.decodeIfPresent(Int.self, forKey: .thumbnailSizeFullSize) ?? thumbnailSizeFullSize
    }
}

struct BrowserExifInfo: Equatable {
    let camera: String?
    let lens: String?
    let exposure: String?
    let aperture: String?
    let focalLength: String?
    let iso: String?
    let capturedAt: String?
    let dimensions: String?
    let focusPoint: BrowserFocusPoint?

    nonisolated var rows: [(String, String)] {
        [
            ("Camera", camera),
            ("Lens", lens),
            ("Exposure", exposure),
            ("Aperture", aperture),
            ("Focal Length", focalLength),
            ("ISO", iso),
            ("Captured", capturedAt),
            ("Dimensions", dimensions),
            ("Focus Point", focusPoint?.description)
        ].compactMap { label, value in
            guard let value, !value.isEmpty else { return nil }
            return (label, value)
        }
    }

    nonisolated var isEmpty: Bool {
        rows.isEmpty
    }
}

struct BrowserFocusPoint: Equatable {
    let normalizedX: Double
    let normalizedY: Double

    nonisolated var description: String {
        "\(Int((normalizedX * 100).rounded()))%, \(Int((normalizedY * 100).rounded()))%"
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
