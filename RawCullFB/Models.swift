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

struct BrowserExifInfo: Equatable, Sendable {
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
            ("Focus Point", focusPoint?.description),
        ].compactMap { label, value in
            guard let value, !value.isEmpty else { return nil }
            return (label, value)
        }
    }

    nonisolated var isEmpty: Bool {
        rows.isEmpty
    }
}

struct BrowserFocusPoint: Equatable, Sendable {
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
