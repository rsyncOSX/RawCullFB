import CoreImage
import Foundation
import RawParserKit

/// Checks the installed decoder's capabilities without rendering sensor data.
nonisolated enum RAW9Support {
    static func preferredVersion(in versions: [CIRAWDecoderVersion]) -> CIRAWDecoderVersion? {
        if versions.contains(.version9) { return .version9 }
        if versions.contains(.version9DNG) { return .version9DNG }
        return nil
    }

    @concurrent
    static func isSupported(for url: URL) async -> Bool {
        guard !Task.isCancelled, !SupportedFileType.isRenderedImage(url) else { return false }
        return autoreleasepool {
            guard let filter = CIRAWFilter(imageURL: url) else { return false }
            return preferredVersion(in: filter.supportedDecoderVersions) != nil
        }
    }
}
