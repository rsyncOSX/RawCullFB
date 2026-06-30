import Foundation

struct BrowserSettings: Codable {
    nonisolated static let defaultMemoryCacheSizeMB = 768
    nonisolated static let defaultGridCacheSizeMB = 1024
    nonisolated static let defaultMaxCachedExtractedJPGs = 4
    private nonisolated static let legacyDefaultGridCacheSizeMB = 256

    var memoryCacheSizeMB = defaultMemoryCacheSizeMB
    var gridCacheSizeMB = defaultGridCacheSizeMB
    var maxCachedExtractedJPGs = defaultMaxCachedExtractedJPGs
    var thumbnailSizeGrid = 200
    var thumbnailSizePreview = 1616
    var thumbnailSizeFullSize = 8700
    var enableRatingPins = true

    enum CodingKeys: String, CodingKey {
        case memoryCacheSizeMB
        case gridCacheSizeMB
        case maxCachedExtractedJPGs
        case thumbnailSizeGrid
        case thumbnailSizePreview
        case thumbnailSizeFullSize
        case enableRatingPins
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        memoryCacheSizeMB = try min(
            container.decodeIfPresent(Int.self, forKey: .memoryCacheSizeMB) ?? memoryCacheSizeMB,
            Self.defaultMemoryCacheSizeMB,
        )
        let decodedGridCacheSizeMB = try container.decodeIfPresent(Int.self, forKey: .gridCacheSizeMB)
        gridCacheSizeMB = if decodedGridCacheSizeMB == Self.legacyDefaultGridCacheSizeMB {
            Self.defaultGridCacheSizeMB
        } else {
            min(decodedGridCacheSizeMB ?? gridCacheSizeMB, Self.defaultGridCacheSizeMB)
        }
        maxCachedExtractedJPGs = try min(
            container.decodeIfPresent(Int.self, forKey: .maxCachedExtractedJPGs) ?? maxCachedExtractedJPGs,
            Self.defaultMaxCachedExtractedJPGs,
        )
        thumbnailSizeGrid = try container.decodeIfPresent(Int.self, forKey: .thumbnailSizeGrid) ?? thumbnailSizeGrid
        thumbnailSizePreview = try container.decodeIfPresent(Int.self, forKey: .thumbnailSizePreview) ?? thumbnailSizePreview
        thumbnailSizeFullSize = try container.decodeIfPresent(Int.self, forKey: .thumbnailSizeFullSize) ?? thumbnailSizeFullSize
        enableRatingPins = try container.decodeIfPresent(Bool.self, forKey: .enableRatingPins) ?? enableRatingPins
    }
}
