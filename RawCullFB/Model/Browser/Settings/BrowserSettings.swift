import Foundation

nonisolated struct BrowserSettings: Codable, Equatable, Sendable {
    nonisolated static let defaultMemoryCacheSizeMB = 768
    nonisolated static let defaultGridCacheSizeMB = 768
    nonisolated static let defaultMaxCachedExtractedJPGs = 4
    private nonisolated static let legacyDefaultGridCacheSizeMB = 256

    var memoryCacheSizeMB = defaultMemoryCacheSizeMB
    var gridCacheSizeMB = defaultGridCacheSizeMB
    var maxCachedExtractedJPGs = defaultMaxCachedExtractedJPGs
    var thumbnailSizeGrid = 200
    var thumbnailSizePreview = 1616
    var thumbnailSizeFullSize = 8700
    var enableRatingPins = true
    var clipModelPath: String?
    var semanticSearchLimit = 50
    var lastIndexedDirectoryPath: String?

    enum CodingKeys: String, CodingKey {
        case memoryCacheSizeMB
        case gridCacheSizeMB
        case maxCachedExtractedJPGs
        case thumbnailSizeGrid
        case thumbnailSizePreview
        case thumbnailSizeFullSize
        case enableRatingPins
        case clipModelPath
        case semanticSearchLimit
        case lastIndexedDirectoryPath
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
        clipModelPath = try container.decodeIfPresent(String.self, forKey: .clipModelPath)
        semanticSearchLimit = min(
            max(try container.decodeIfPresent(Int.self, forKey: .semanticSearchLimit) ?? semanticSearchLimit, 10),
            500,
        )
        lastIndexedDirectoryPath = try container.decodeIfPresent(String.self, forKey: .lastIndexedDirectoryPath)
    }
}
