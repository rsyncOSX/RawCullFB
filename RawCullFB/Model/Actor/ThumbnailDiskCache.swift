import AppKit
import CryptoKit
import Foundation
import ImageIO
import OSLog
import UniformTypeIdentifiers

actor ThumbnailDiskCache {
    private static let cacheKeyVersion = "v2-oriented-thumbnails"
    static let shared = ThumbnailDiskCache()

    let cacheDirectory: URL

    init(cacheDirectory: URL? = nil) {
        let folder: URL
        if let cacheDirectory {
            folder = cacheDirectory
        } else {
            let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
            folder = paths[0]
                .appendingPathComponent("RawCullFB", isDirectory: true)
                .appendingPathComponent("Thumbnails", isDirectory: true)
        }
        self.cacheDirectory = folder
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            Logger.process.warning("ThumbnailDiskCache: Failed to create directory \(folder): \(error)")
        }
    }

    private func cacheURL(for sourceURL: URL, maxPixelSize: Int) -> URL {
        let standardizedPath = sourceURL.standardized.path
        let data = Data("\(Self.cacheKeyVersion):\(standardizedPath):\(max(maxPixelSize, 1))".utf8)
        let digest = Insecure.MD5.hash(data: data)
        let hash = digest.map { String(format: "%02x", $0) }.joined()
        return cacheDirectory.appendingPathComponent(hash).appendingPathExtension("jpg")
    }

    func load(for sourceURL: URL, maxPixelSize: Int) async -> NSImage? {
        let fileURL = cacheURL(for: sourceURL, maxPixelSize: maxPixelSize)

        return await Task.detached(priority: .userInitiated) {
            guard let image = OrientationNormalizedImageLoader.loadCGImage(from: fileURL) else { return nil }
            return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        }.value
    }

    func save(_ jpegData: Data, for sourceURL: URL, maxPixelSize: Int) async {
        let fileURL = cacheURL(for: sourceURL, maxPixelSize: maxPixelSize)

        await Task.detached(priority: .background) {
            do {
                try jpegData.write(to: fileURL, options: .atomic)
            } catch {
                Logger.process.warning("ThumbnailDiskCache: Failed to write image to disk \(fileURL.path): \(error)")
            }
        }.value
    }

    nonisolated static func jpegData(from cgImage: CGImage) -> Data? {
        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            mutableData,
            UTType.jpeg.identifier as CFString,
            1,
            nil,
        ) else { return nil }

        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.7]
        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return mutableData as Data
    }
}
