import AppKit
import ImageIO
import RawParserKit

actor RawImageLoader {
    static let shared = RawImageLoader()

    private var thumbnailTasks: [URL: Task<NSImage?, Never>] = [:]
    private var extractedJPGTasks: [URL: Task<CGImage?, Never>] = [:]

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
