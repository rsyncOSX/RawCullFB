import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

actor ZoomPreviewDiskCache {
    static let shared = ZoomPreviewDiskCache()

    private let cacheVersion = 1
    private let maxCacheBytes: Int64 = 5 * 1024 * 1024 * 1024
    private let fileManager = FileManager.default

    private init() {}

    func cachedImage(for sourceURL: URL, maxPixelSize: Int) async -> CGImage? {
        let fileURL = cacheFileURL(for: sourceURL, maxPixelSize: maxPixelSize)
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }

        touch(fileURL)
        return await Task.detached(priority: .userInitiated) {
            OrientationNormalizedImageLoader.loadCGImage(from: fileURL)
        }.value
    }

    func store(_ image: CGImage, for sourceURL: URL, maxPixelSize: Int) async {
        let fileURL = cacheFileURL(for: sourceURL, maxPixelSize: maxPixelSize)

        do {
            try fileManager.createDirectory(
                at: cacheDirectoryURL,
                withIntermediateDirectories: true,
            )
            let temporaryURL = fileURL
                .deletingLastPathComponent()
                .appendingPathComponent("\(fileURL.lastPathComponent).tmp")
            try? fileManager.removeItem(at: temporaryURL)
            guard writeJPEG(image, to: temporaryURL) else { return }
            try? fileManager.removeItem(at: fileURL)
            try fileManager.moveItem(at: temporaryURL, to: fileURL)
            touch(fileURL)
            evictIfNeeded()
        } catch {
            return
        }
    }

    private var cacheDirectoryURL: URL {
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches
            .appendingPathComponent("RawCullFB", isDirectory: true)
            .appendingPathComponent("ZoomPreviewCache", isDirectory: true)
    }

    private func cacheFileURL(for sourceURL: URL, maxPixelSize: Int) -> URL {
        cacheDirectoryURL
            .appendingPathComponent(cacheKey(for: sourceURL, maxPixelSize: maxPixelSize))
            .appendingPathExtension("jpg")
    }

    private func cacheKey(for sourceURL: URL, maxPixelSize: Int) -> String {
        let standardizedURL = sourceURL.standardizedFileURL
        let values = try? standardizedURL.resourceValues(forKeys: [
            .fileSizeKey,
            .contentModificationDateKey
        ])
        let fileSize = values?.fileSize ?? 0
        let modifiedAt = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        let key = [
            "v\(cacheVersion)",
            standardizedURL.path,
            "\(fileSize)",
            "\(modifiedAt)",
            "\(max(maxPixelSize, 1))"
        ].joined(separator: "|")

        let digest = SHA256.hash(data: Data(key.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func writeJPEG(_ image: CGImage, to fileURL: URL) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(
            fileURL as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil,
        ) else { return false }

        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.92
        ]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        return CGImageDestinationFinalize(destination)
    }

    private func touch(_ fileURL: URL) {
        try? fileManager.setAttributes(
            [.modificationDate: Date()],
            ofItemAtPath: fileURL.path,
        )
    }

    private func evictIfNeeded() {
        guard let files = try? fileManager.contentsOfDirectory(
            at: cacheDirectoryURL,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles],
        ) else { return }

        var entries: [(url: URL, size: Int64, modifiedAt: Date)] = []
        var totalSize: Int64 = 0

        for file in files where file.pathExtension.localizedCaseInsensitiveCompare("jpg") == .orderedSame {
            let values = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let size = Int64(values?.fileSize ?? 0)
            totalSize += size
            entries.append((file, size, values?.contentModificationDate ?? .distantPast))
        }

        guard totalSize > maxCacheBytes else { return }

        for entry in entries.sorted(by: { $0.modifiedAt < $1.modifiedAt }) {
            try? fileManager.removeItem(at: entry.url)
            totalSize -= entry.size
            if totalSize <= maxCacheBytes {
                break
            }
        }
    }
}
