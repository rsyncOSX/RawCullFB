import AppKit
import ImageIO
import RawParserKit

actor RawImageLoader {
    static let shared = RawImageLoader()

    private struct ImageTaskKey: Hashable {
        let url: URL
        let maxPixelSize: Int
    }

    private var thumbnailTasks: [ImageTaskKey: Task<NSImage?, Never>] = [:]
    private var extractedJPGTasks: [URL: Task<CGImage?, Never>] = [:]

    private init() {}

    private nonisolated static var fullSizeCache: FullSizeJPGDiskCache {
        FullSizeJPGDiskCache.shared
    }

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
                return Self.folderItem(at: url)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }.value
    }

    func folderItem(at folderURL: URL) async -> BrowserFolderItem {
        await Task.detached(priority: .utility) {
            Self.folderItem(at: folderURL)
        }.value
    }

    func discoverSupportedFiles(at folderURL: URL) async -> [BrowserFileItem] {
        await Task.detached(priority: .utility) {
            let supported = RawFormatRegistry.allExtensions.union(SupportedFileType.renderedImageExtensions)
            let keys: Set<URLResourceKey> = [.isRegularFileKey, .isHiddenKey]
            guard let children = try? FileManager.default.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
            ) else { return [] }

            let files = children.compactMap { url -> BrowserFileItem? in
                guard supported.contains(url.pathExtension.lowercased()) else { return nil }
                let values = try? url.resourceValues(forKeys: keys)
                guard values?.isRegularFile == true, values?.isHidden != true else { return nil }
                return BrowserFileItem(url: url)
            }
            let renderedImageFiles = files.filter { SupportedFileType.isRenderedImage($0.url) }
            return (renderedImageFiles.isEmpty ? files : renderedImageFiles)
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }.value
    }

    func thumbnail(for url: URL, targetSize: Int = 200) async -> NSImage? {
        let boundedTargetSize = max(targetSize, 1)
        let taskKey = ImageTaskKey(url: url, maxPixelSize: boundedTargetSize)

        if let cached = await MemoryImageCache.shared.thumbnail(for: url, maxPixelSize: boundedTargetSize) {
            return cached
        }

        if let existing = thumbnailTasks[taskKey] {
            return await existing.value
        }

        let task = Task<NSImage?, Never>(priority: .utility) {
            if let diskImage = await ThumbnailDiskCache.shared.load(
                for: url,
                maxPixelSize: boundedTargetSize,
            ) {
                await MemoryImageCache.shared.storeThumbnail(
                    diskImage,
                    for: url,
                    maxPixelSize: boundedTargetSize,
                )
                return diskImage
            }

            guard let image = await RawParserKit.RawImageLoader.shared.thumbnail(
                for: url,
                maxPixelSize: boundedTargetSize,
            ), !Task.isCancelled else { return nil }

            await MemoryImageCache.shared.storeThumbnail(image, for: url, maxPixelSize: boundedTargetSize)
            if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
               let jpegData = ThumbnailDiskCache.jpegData(from: cgImage) {
                await ThumbnailDiskCache.shared.save(
                    jpegData,
                    for: url,
                    maxPixelSize: boundedTargetSize,
                )
            }
            return image
        }

        thumbnailTasks[taskKey] = task
        let image = await task.value
        thumbnailTasks[taskKey] = nil
        return image
    }

    func previewImage(for url: URL, maxPixelSize _: Int) async -> CGImage? {
        if let existing = extractedJPGTasks[url] {
            return await existing.value
        }

        for (staleURL, staleTask) in extractedJPGTasks where staleURL != url {
            staleTask.cancel()
            extractedJPGTasks[staleURL] = nil
        }

        let task = Task<CGImage?, Never>(priority: .userInitiated) {
            guard !Task.isCancelled else { return nil }

            if SupportedFileType.isRenderedImage(url) {
                return await Self.loadCGImage(from: url)
            }

            if let cached = await Self.fullSizeCache.load(for: url) {
                guard !Task.isCancelled else { return nil }
                return cached
            }

            let extracted = await RawParserKit.RawImageLoader.shared.previewImage(for: url)
            guard !Task.isCancelled else { return nil }

            if let extracted {
                let sourceJPEGData = await Self.embeddedPreviewJPEGData(
                    for: url,
                    matchingPixelWidth: extracted.width,
                    height: extracted.height,
                )
                guard !Task.isCancelled else { return nil }

                if let jpegData = sourceJPEGData ?? FullSizeJPGDiskCache.jpegData(from: extracted) {
                    await Self.fullSizeCache.save(jpegData, for: url)
                }
            }

            return extracted
        }

        extractedJPGTasks[url] = task
        let image = await task.value
        extractedJPGTasks[url] = nil
        return image
    }

    /// Cancels any in-flight full-size preview extraction(s). Call this when
    /// the zoom overlay is dismissed so an abandoned decode doesn't keep
    /// running (and holding memory) in the background.
    func cancelPreview() {
        for (_, task) in extractedJPGTasks {
            task.cancel()
        }
        extractedJPGTasks.removeAll()
    }

    func metadata(for url: URL) async -> RawImageMetadata? {
        await RawParserKit.RawImageLoader.shared.metadata(for: url)
    }

    private nonisolated static func loadCGImage(from url: URL) async -> CGImage? {
        await Task.detached(priority: .userInitiated) {
            OrientationNormalizedImageLoader.loadCGImage(from: url)
        }.value
    }

    /// Returns camera-authored JPEG bytes only when they match the preview
    /// selected by RawParserKit, avoiding a second lossy full-size encode.
    @concurrent private static func embeddedPreviewJPEGData(
        for url: URL,
        matchingPixelWidth pixelWidth: Int,
        height pixelHeight: Int,
    ) async -> Data? {
        guard !Task.isCancelled else { return nil }

        switch url.pathExtension.lowercased() {
        case SupportedFileType.arw.rawValue:
            guard let locations = SonyMakerNoteParser.embeddedJPEGLocations(from: url) else {
                return nil
            }
            for location in [locations.fullJPEG, locations.preview, locations.thumbnail].compactMap(\.self) {
                guard !Task.isCancelled else { return nil }
                if let data = SonyMakerNoteParser.readEmbeddedJPEGData(at: location, from: url),
                   jpegData(data, matchesPixelWidth: pixelWidth, height: pixelHeight) {
                    return data
                }
            }

        case SupportedFileType.nef.rawValue:
            guard let locations = NikonMakerNoteParser.embeddedJPEGLocations(from: url) else {
                return nil
            }
            for location in [locations.preview, locations.ifd1JPEG].compactMap(\.self) {
                guard !Task.isCancelled else { return nil }
                if let data = NikonMakerNoteParser.readEmbeddedJPEGData(at: location, from: url),
                   jpegData(data, matchesPixelWidth: pixelWidth, height: pixelHeight) {
                    return data
                }
            }

        default:
            return nil
        }
        return nil
    }

    private nonisolated static func jpegData(
        _ data: Data,
        matchesPixelWidth pixelWidth: Int,
        height pixelHeight: Int,
    ) -> Bool {
        guard let dimensions = jpegPixelDimensions(from: data) else { return false }
        return (dimensions.width == pixelWidth && dimensions.height == pixelHeight)
            || (dimensions.width == pixelHeight && dimensions.height == pixelWidth)
    }

    private nonisolated static func jpegPixelDimensions(
        from data: Data,
    ) -> (width: Int, height: Int)? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options),
              let properties = CGImageSourceCopyPropertiesAtIndex(
                  source,
                  0,
                  options,
              ) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
        else { return nil }
        return (width, height)
    }

    private nonisolated static func supportedFileCount(in folderURL: URL) -> Int {
        let supported = RawFormatRegistry.allExtensions.union(SupportedFileType.renderedImageExtensions)
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
        ) else { return 0 }

        let supportedFiles = children.filter { url in
            guard supported.contains(url.pathExtension.lowercased()) else { return false }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            return values?.isRegularFile == true
        }
        let renderedImageCount = supportedFiles.count(where: SupportedFileType.isRenderedImage)
        return renderedImageCount > 0 ? renderedImageCount : supportedFiles.count
    }

    private nonisolated static func folderItem(at folderURL: URL) -> BrowserFolderItem {
        BrowserFolderItem(
            url: folderURL,
            supportedFileCount: supportedFileCount(in: folderURL),
            hasCLIPIndex: CLIPIndexPaths.containsIndex(in: folderURL),
        )
    }
}
