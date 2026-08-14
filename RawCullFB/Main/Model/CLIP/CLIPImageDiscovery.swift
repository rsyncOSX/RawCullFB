import CoreGraphics
import Foundation
import ImageIO
import PhotoAIContracts
import RawParserKit

nonisolated enum CLIPImageDiscovery {
    static let supportedExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "arw"
    ]

    static func sources(in directory: URL) throws -> [AIImageSource] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isHiddenKey]
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
        ) else {
            throw CLIPFeatureError.cannotReadDirectory(directory.path)
        }

        return try enumerator.compactMap { element in
            guard let url = element as? URL,
                  supportedExtensions.contains(url.pathExtension.lowercased())
            else { return nil }

            let values = try url.resourceValues(forKeys: keys)
            guard values.isRegularFile == true, values.isHidden != true else { return nil }
            return AIImageSource(
                id: UUID(),
                url: url.standardizedFileURL,
                displayName: url.lastPathComponent,
            )
        }
        .sorted {
            $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending
        }
    }
}

nonisolated struct CLIPImageDecoder: ImageDecoding {
    let thumbnailMaximumPixelSize: Int

    init(thumbnailMaximumPixelSize: Int = 2048) {
        self.thumbnailMaximumPixelSize = thumbnailMaximumPixelSize
    }

    func image(for source: AIImageSource) async throws -> CGImage {
        try Task.checkCancellation()
        if source.url.pathExtension.lowercased() == "arw" {
            guard let image = await SonyEmbeddedJPEGExtractor.extractEmbeddedJPEG(from: source.url)
            else {
                throw CLIPFeatureError.cannotDecodeImage(source.url.path)
            }
            try Task.checkCancellation()
            return image
        }

        guard let imageSource = CGImageSourceCreateWithURL(source.url as CFURL, nil) else {
            throw CLIPFeatureError.cannotDecodeImage(source.url.path)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbnailMaximumPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(
            imageSource,
            0,
            options as CFDictionary,
        ) else {
            throw CLIPFeatureError.cannotDecodeImage(source.url.path)
        }
        return image
    }
}
