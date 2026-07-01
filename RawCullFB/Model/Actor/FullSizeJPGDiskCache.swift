import CryptoKit
import Foundation
import ImageIO
import OSLog
import UniformTypeIdentifiers

actor FullSizeJPGDiskCache {
    nonisolated enum Variant: String {
        case embeddedJPG
        case developedRAW
    }

    private static let cacheKeyVersion = "v5-embedded-jpg-orientation"
    static let shared = FullSizeJPGDiskCache()

    let cacheDirectory: URL

    init(cacheDirectory: URL? = nil) {
        let folder: URL
        if let cacheDirectory {
            folder = cacheDirectory
        } else {
            let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
            folder = paths[0]
                .appendingPathComponent("RawCullFB", isDirectory: true)
                .appendingPathComponent("FullsizeJPGs", isDirectory: true)
        }
        self.cacheDirectory = folder
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            Logger.process.warning("FullSizeJPGDiskCache: Failed to create directory \(folder): \(error)")
        }
    }

    private func cacheURL(for sourceURL: URL, variant: Variant) -> URL {
        let standardizedPath = sourceURL.standardized.path
        let variantKey = variant == .embeddedJPG ? "" : ":\(variant.rawValue)"
        let data = Data("\(Self.cacheKeyVersion):\(standardizedPath)\(variantKey)".utf8)
        let digest = Insecure.MD5.hash(data: data)
        let hash = digest.map { String(format: "%02x", $0) }.joined()
        return cacheDirectory.appendingPathComponent(hash).appendingPathExtension("jpg")
    }

    /// Loads a cached full-size JPEG as a `CGImage`.
    /// Uses `kCGImageSourceShouldCache: false` and `CGImageSourceRemoveCacheAtIndex`
    /// to prevent ImageIO from retaining the decoded full-resolution pixel buffer
    /// in its process-level cache.
    func load(for sourceURL: URL, variant: Variant = .embeddedJPG) async -> CGImage? {
        let fileURL = cacheURL(for: sourceURL, variant: variant)

        return await Task.detached(priority: .userInitiated) {
            OrientationNormalizedImageLoader.loadCGImage(from: fileURL)
        }.value
    }

    func save(_ jpegData: Data, for sourceURL: URL, variant: Variant = .embeddedJPG) async {
        let fileURL = cacheURL(for: sourceURL, variant: variant)

        await Task.detached(priority: .background) {
            do {
                try jpegData.write(to: fileURL, options: .atomic)
            } catch {
                Logger.process.warning("FullSizeJPGDiskCache: Failed to write image to disk \(fileURL.path): \(error)")
            }
        }.value
    }

    /// Encodes a `CGImage` to JPEG `Data` at quality 0.85. Call this before
    /// crossing actor/task boundaries with an extracted full-size image.
    nonisolated static func jpegData(from cgImage: CGImage) -> Data? {
        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            mutableData,
            UTType.jpeg.identifier as CFString,
            1,
            nil,
        ) else { return nil }

        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.85]
        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return mutableData as Data
    }
}
