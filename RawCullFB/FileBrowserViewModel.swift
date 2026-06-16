import CoreGraphics
import Foundation
import Observation

@Observable @MainActor
final class FileBrowserViewModel {
    var rootFolders: [BrowserFolderItem] = []
    var folderChildren: [BrowserFolderItem.ID: [BrowserFolderItem]] = [:]
    var expandedFolderIDs: Set<BrowserFolderItem.ID> = []
    var loadingFolderIDs: Set<BrowserFolderItem.ID> = []
    var files: [BrowserFileItem] = []
    var selectedFolder: BrowserFolderItem?
    var selectedFileID: BrowserFileItem.ID?
    var isShowingFolderPicker = false
    var isScanning = false
    var isCreatingThumbnails = false
    var zoomOverlayVisible = false
    var zoomImage: CGImage?
    var zoomExifInfo: BrowserExifInfo?
    var zoomScale: CGFloat = 1.0
    var zoomOffset: CGSize = .zero
    var isZoomMetadataCollapsed = false
    var zoomMetadataOffset: CGSize = .zero
    var isZoomFocusPointVisible = false
    var settings = BrowserSettings()

    @ObservationIgnored private var activeSecurityScopedURL: URL?
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var thumbnailTask: Task<Void, Never>?
    @ObservationIgnored private var zoomTask: Task<Void, Never>?
    @ObservationIgnored private var scanID = UUID()

    var selectedFile: BrowserFileItem? {
        files.first { $0.id == selectedFileID }
    }

    var isSidebarSelectionEnabled: Bool {
        !isCreatingThumbnails
    }

    var title: String {
        guard let selectedFolder else { return "RawCullFB" }
        return "\(selectedFolder.name) (\(files.count) files)"
    }

    func loadSettings() async {
        settings = await BrowserSettingsStore.load()
        await MemoryImageCache.shared.apply(settings: settings)
    }

    func addRootFolder(_ url: URL) {
        guard startSecurityScopedAccess(for: url) else { return }
        let folder = BrowserFolderItem(url: url)
        if !rootFolders.contains(where: { $0.url == url }) {
            rootFolders.append(folder)
            rootFolders.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        selectFolder(folder)
    }

    func children(of folder: BrowserFolderItem) -> [BrowserFolderItem] {
        folderChildren[folder.id] ?? []
    }

    func hasLoadedChildren(for folder: BrowserFolderItem) -> Bool {
        folderChildren[folder.id] != nil
    }

    func isFolderExpanded(_ folder: BrowserFolderItem) -> Bool {
        expandedFolderIDs.contains(folder.id)
    }

    func setFolder(_ folder: BrowserFolderItem, expanded: Bool) {
        if expanded {
            expandedFolderIDs.insert(folder.id)
            loadChildrenIfNeeded(for: folder)
        } else {
            expandedFolderIDs.remove(folder.id)
        }
    }

    func folder(for id: BrowserFolderItem.ID) -> BrowserFolderItem? {
        rootFolders.first { $0.id == id } ?? folderChildren.values.lazy.flatMap { $0 }.first { $0.id == id }
    }

    func selectFolder(_ folder: BrowserFolderItem) {
        guard isSidebarSelectionEnabled else { return }
        guard startSecurityScopedAccess(for: securityScopedURL(for: folder.url)) else { return }

        let currentScanID = UUID()
        scanID = currentScanID
        selectedFolder = folder
        selectedFileID = nil
        resetZoomInterfaceState()
        isCreatingThumbnails = false
        scanTask?.cancel()
        thumbnailTask?.cancel()
        closeZoom()

        scanTask = Task {
            isScanning = true
            async let folders = RawImageLoader.shared.discoverFolders(at: folder.url)
            async let discoveredFiles = RawImageLoader.shared.discoverSupportedFiles(at: folder.url)
            let (loadedFolders, loadedFiles) = await (folders, discoveredFiles)
            guard !Task.isCancelled, currentScanID == scanID else { return }
            folderChildren[folder.id] = loadedFolders
            files = loadedFiles
            selectedFileID = loadedFiles.first?.id
            isScanning = false

            guard !loadedFiles.isEmpty else { return }
            isCreatingThumbnails = true
            thumbnailTask = Task {
                await RawImageLoader.shared.preloadThumbnails(for: loadedFiles, targetSize: 200)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard currentScanID == self.scanID else { return }
                    self.isCreatingThumbnails = false
                }
            }
        }
    }

    private func loadChildrenIfNeeded(for folder: BrowserFolderItem) {
        guard folderChildren[folder.id] == nil, !loadingFolderIDs.contains(folder.id) else { return }

        loadingFolderIDs.insert(folder.id)
        Task {
            let loadedFolders = await RawImageLoader.shared.discoverFolders(at: folder.url)
            guard !Task.isCancelled else { return }
            folderChildren[folder.id] = loadedFolders
            loadingFolderIDs.remove(folder.id)
        }
    }

    func selectFile(_ file: BrowserFileItem) {
        selectedFileID = file.id
    }

    func openZoom(for file: BrowserFileItem? = nil) {
        if let file {
            selectedFileID = file.id
        }
        guard let selectedFile else { return }

        zoomTask?.cancel()
        zoomImage = nil
        zoomExifInfo = nil
        zoomOverlayVisible = true
        zoomTask = Task {
            async let image = RawImageLoader.shared.extractedJPG(for: selectedFile.url)
            async let exifInfo = RawImageLoader.shared.exifInfo(for: selectedFile.url)
            let (loadedImage, loadedExifInfo) = await (image, exifInfo)
            guard !Task.isCancelled else { return }
            zoomImage = loadedImage
            zoomExifInfo = loadedExifInfo
        }
    }

    func closeZoom() {
        zoomTask?.cancel()
        zoomTask = nil
        zoomOverlayVisible = false
        zoomImage = nil
        zoomExifInfo = nil
    }

    func resetZoomInterfaceState() {
        zoomScale = 1.0
        zoomOffset = .zero
        isZoomMetadataCollapsed = false
        zoomMetadataOffset = .zero
        isZoomFocusPointVisible = false
    }

    func navigateSelection(by delta: Int) {
        guard let selectedFile,
              let currentIndex = files.firstIndex(of: selectedFile)
        else { return }

        let nextIndex = currentIndex + delta
        guard files.indices.contains(nextIndex) else { return }
        selectedFileID = files[nextIndex].id
        if zoomOverlayVisible {
            openZoom(for: files[nextIndex])
        }
    }

    func stopActiveSecurityScopedAccess() {
        activeSecurityScopedURL?.stopAccessingSecurityScopedResource()
        activeSecurityScopedURL = nil
    }

    private func securityScopedURL(for folderURL: URL) -> URL {
        let standardizedFolderURL = folderURL.standardizedFileURL
        return rootFolders
            .map(\.url)
            .filter { rootURL in
                standardizedFolderURL.isEqualOrDescendant(of: rootURL.standardizedFileURL)
            }
            .max { first, second in
                first.standardizedFileURL.pathComponents.count < second.standardizedFileURL.pathComponents.count
            } ?? folderURL
    }

    private func startSecurityScopedAccess(for url: URL) -> Bool {
        if activeSecurityScopedURL == url {
            return true
        }

        if activeSecurityScopedURL != url {
            stopActiveSecurityScopedAccess()
        }
        guard url.startAccessingSecurityScopedResource() else { return false }
        activeSecurityScopedURL = url
        return true
    }
}

private extension URL {
    func isEqualOrDescendant(of ancestorURL: URL) -> Bool {
        let pathComponents = standardizedFileURL.pathComponents
        let ancestorPathComponents = ancestorURL.standardizedFileURL.pathComponents

        guard pathComponents.count >= ancestorPathComponents.count else { return false }
        return zip(pathComponents, ancestorPathComponents).allSatisfy(==)
    }
}
