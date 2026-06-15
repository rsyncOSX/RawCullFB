import AppKit
import ImageIO
import RawParserKit

actor RawImageLoader {
    static let shared = RawImageLoader()

    private var thumbnailTasks: [URL: Task<NSImage?, Never>] = [:]
    private var extractedJPGTasks: [URL: Task<CGImage?, Never>] = [:]
    private var exifInfoTasks: [URL: Task<BrowserExifInfo?, Never>] = [:]

    private init() {}

    func discoverFolders(at folderURL: URL) async -> [BrowserFolderItem] {
        await Task.detached(priority: .utility) {
            let keys: Set<URLResourceKey> = [.isDirectoryKey, .isHiddenKey]
            guard let children = try? FileManager.default.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsPackageDescendants],
            ) else { return [] }

            return children.compactMap { url -> BrowserFolderItem? in
                let values = try? url.resourceValues(forKeys: keys)
                guard values?.isDirectory == true, values?.isHidden != true else { return nil }
                return BrowserFolderItem(url: url, supportedFileCount: Self.supportedFileCount(in: url))
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }.value
    }

    func discoverSupportedFiles(at folderURL: URL) async -> [BrowserFileItem] {
        await Task.detached(priority: .utility) {
            let supported = RawFormatRegistry.allExtensions
            let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey, .isHiddenKey]
            guard let children = try? FileManager.default.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
            ) else { return [] }

            return children.compactMap { url -> BrowserFileItem? in
                guard supported.contains(url.pathExtension.lowercased()) else { return nil }
                let values = try? url.resourceValues(forKeys: keys)
                guard values?.isRegularFile == true, values?.isHidden != true else { return nil }
                return BrowserFileItem(
                    url: url,
                    byteCount: Int64(values?.fileSize ?? 0),
                    modifiedDate: values?.contentModificationDate,
                )
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }.value
    }

    func preloadThumbnails(for files: [BrowserFileItem], targetSize: Int = 200) async {
        await withTaskGroup(of: Void.self) { group in
            let maxConcurrent = max(2, ProcessInfo.processInfo.activeProcessorCount * 2)

            for (index, file) in files.enumerated() {
                if Task.isCancelled {
                    group.cancelAll()
                    break
                }
                if index >= maxConcurrent {
                    await group.next()
                }
                group.addTask {
                    _ = await self.thumbnail(for: file.url, targetSize: targetSize)
                }
            }

            await group.waitForAll()
        }
    }

    func thumbnail(for url: URL, targetSize: Int = 200) async -> NSImage? {
        if let cached = MemoryImageCache.shared.thumbnail(for: url) {
            return cached
        }

        if let existing = thumbnailTasks[url] {
            return await existing.value
        }

        let task = Task<NSImage?, Never>(priority: .utility) {
            guard let format = RawFormatRegistry.format(for: url),
                  let cgImage = try? await format.extractThumbnail(
                    from: url,
                    maxDimension: CGFloat(targetSize),
                    qualityCost: 4,
                  )
            else { return nil }

            let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            MemoryImageCache.shared.storeThumbnail(image, for: url)
            return image
        }

        thumbnailTasks[url] = task
        let image = await task.value
        thumbnailTasks[url] = nil
        return image
    }

    func extractedJPG(for url: URL) async -> CGImage? {
        if let cached = MemoryImageCache.shared.extractedJPG(for: url) {
            return cached
        }

        if let existing = extractedJPGTasks[url] {
            return await existing.value
        }

        let task = Task<CGImage?, Never>(priority: .userInitiated) {
            let sidecarURL = url.deletingPathExtension().appendingPathExtension("jpg")
            if let sidecarImage = await Self.loadCGImage(from: sidecarURL) {
                MemoryImageCache.shared.storeExtractedJPG(sidecarImage, for: url)
                return sidecarImage
            }

            guard let format = RawFormatRegistry.format(for: url),
                  let extracted = await format.extractFullJPEG(from: url, fullSize: false)
            else { return nil }

            MemoryImageCache.shared.storeExtractedJPG(extracted, for: url)
            return extracted
        }

        extractedJPGTasks[url] = task
        let image = await task.value
        extractedJPGTasks[url] = nil
        return image
    }

    func exifInfo(for url: URL) async -> BrowserExifInfo? {
        if let existing = exifInfoTasks[url] {
            return await existing.value
        }

        let task = Task<BrowserExifInfo?, Never>(priority: .utility) {
            await Self.loadExifInfo(from: url)
        }

        exifInfoTasks[url] = task
        let info = await task.value
        exifInfoTasks[url] = nil
        return info
    }

    private nonisolated static func loadCGImage(from url: URL) async -> CGImage? {
        await Task.detached(priority: .userInitiated) {
            let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
            guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
            let decodeOptions = [kCGImageSourceShouldCache: false] as CFDictionary
            guard let image = CGImageSourceCreateImageAtIndex(source, 0, decodeOptions) else { return nil }
            CGImageSourceRemoveCacheAtIndex(source, 0)
            return image
        }.value
    }

    private nonisolated static func loadExifInfo(from url: URL) async -> BrowserExifInfo? {
        await Task.detached(priority: .utility) {
            let sidecarURL = url.deletingPathExtension().appendingPathExtension("jpg")
            guard let properties = imageProperties(from: url) ?? imageProperties(from: sidecarURL) else { return nil }
            let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
            let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]

            let make = stringValue(tiff?[kCGImagePropertyTIFFMake])
            let model = stringValue(tiff?[kCGImagePropertyTIFFModel])
            let camera = joined([make, model])

            let lens = stringValue(exif?[kCGImagePropertyExifLensModel])
            let exposure = shutterDescription(numberValue(exif?[kCGImagePropertyExifExposureTime]))
            let aperture = apertureDescription(numberValue(exif?[kCGImagePropertyExifFNumber]))
            let focalLength = focalLengthDescription(numberValue(exif?[kCGImagePropertyExifFocalLength]))
            let iso = isoDescription(exif?[kCGImagePropertyExifISOSpeedRatings])
            let capturedAt = capturedAtDescription(
                stringValue(exif?[kCGImagePropertyExifDateTimeOriginal]) ?? stringValue(tiff?[kCGImagePropertyTIFFDateTime])
            )
            let dimensions = dimensionsDescription(properties: properties, exif: exif)

            let info = BrowserExifInfo(
                camera: camera,
                lens: lens,
                exposure: exposure,
                aperture: aperture,
                focalLength: focalLength,
                iso: iso,
                capturedAt: capturedAt,
                dimensions: dimensions,
            )
            return info.isEmpty ? nil : info
        }.value
    }

    private nonisolated static func imageProperties(from url: URL) -> [CFString: Any]? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return nil }
        return properties
    }

    private nonisolated static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let value as String:
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case let value as NSNumber:
            return value.stringValue
        default:
            return nil
        }
    }

    private nonisolated static func numberValue(_ value: Any?) -> Double? {
        switch value {
        case let value as NSNumber:
            return value.doubleValue
        case let value as String:
            return Double(value)
        default:
            return nil
        }
    }

    private nonisolated static func intValue(_ value: Any?) -> Int? {
        switch value {
        case let value as NSNumber:
            return value.intValue
        case let value as String:
            return Int(value)
        default:
            return nil
        }
    }

    private nonisolated static func joined(_ values: [String?]) -> String? {
        var parts: [String] = []
        for value in values.compactMap({ $0 }) where !parts.contains(value) {
            parts.append(value)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    private nonisolated static func shutterDescription(_ seconds: Double?) -> String? {
        guard let seconds, seconds > 0 else { return nil }
        if seconds >= 1 {
            return "\(trimmed(seconds)) s"
        }
        return "1/\(Int(round(1 / seconds))) s"
    }

    private nonisolated static func apertureDescription(_ aperture: Double?) -> String? {
        guard let aperture, aperture > 0 else { return nil }
        return "f/\(trimmed(aperture))"
    }

    private nonisolated static func focalLengthDescription(_ focalLength: Double?) -> String? {
        guard let focalLength, focalLength > 0 else { return nil }
        return "\(trimmed(focalLength)) mm"
    }

    private nonisolated static func isoDescription(_ value: Any?) -> String? {
        if let values = value as? [Any],
           let iso = values.compactMap({ intValue($0) }).first {
            return "\(iso)"
        }
        if let iso = intValue(value) {
            return "\(iso)"
        }
        return nil
    }

    private nonisolated static func capturedAtDescription(_ value: String?) -> String? {
        guard let value else { return nil }
        let parser = DateFormatter()
        parser.dateFormat = "yyyy:MM:dd HH:mm:ss"
        parser.locale = Locale(identifier: "en_US_POSIX")

        guard let date = parser.date(from: value) else { return value }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private nonisolated static func dimensionsDescription(properties: [CFString: Any], exif: [CFString: Any]?) -> String? {
        let width = intValue(properties[kCGImagePropertyPixelWidth]) ?? intValue(exif?[kCGImagePropertyExifPixelXDimension])
        let height = intValue(properties[kCGImagePropertyPixelHeight]) ?? intValue(exif?[kCGImagePropertyExifPixelYDimension])
        guard let width, let height, width > 0, height > 0 else { return nil }
        return "\(width) x \(height)"
    }

    private nonisolated static func trimmed(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return "\(Int(rounded))"
        }
        return String(format: "%.1f", rounded)
    }

    private nonisolated static func supportedFileCount(in folderURL: URL) -> Int {
        let supported = RawFormatRegistry.allExtensions
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
        ) else { return 0 }

        return children.reduce(into: 0) { count, url in
            guard supported.contains(url.pathExtension.lowercased()) else { return }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            if values?.isRegularFile == true {
                count += 1
            }
        }
    }
}
