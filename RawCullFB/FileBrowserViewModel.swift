import CoreGraphics
import Foundation
import Observation

@Observable @MainActor
final class FileBrowserViewModel {
    var rootFolders: [BrowserFolderItem] = []
    var childFolders: [BrowserFolderItem] = []
    var files: [BrowserFileItem] = []
    var selectedFolder: BrowserFolderItem?
    var selectedFileID: BrowserFileItem.ID?
    var displayMode: BrowserDisplayMode = .grid
    var isShowingFolderPicker = false
    var isScanning = false
    var isCreatingThumbnails = false
    var zoomOverlayVisible = false
    var zoomImage: CGImage?
    var settings = BrowserSettings()

    @ObservationIgnored private var activeSecurityScopedURL: URL?
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var thumbnailTask: Task<Void, Never>?
    @ObservationIgnored private var zoomTask: Task<Void, Never>?

    var selectedFile: BrowserFileItem? {
        files.first { $0.id == selectedFileID }
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

    func selectFolder(_ folder: BrowserFolderItem) {
        selectedFolder = folder
        selectedFileID = nil
        scanTask?.cancel()
        thumbnailTask?.cancel()

        scanTask = Task {
            isScanning = true
            async let folders = RawImageLoader.shared.discoverFolders(at: folder.url)
            async let discoveredFiles = RawImageLoader.shared.discoverSupportedFiles(at: folder.url)
            let (loadedFolders, loadedFiles) = await (folders, discoveredFiles)
            guard !Task.isCancelled else { return }
            childFolders = loadedFolders
            files = loadedFiles
            selectedFileID = loadedFiles.first?.id
            isScanning = false

            guard !loadedFiles.isEmpty else { return }
            isCreatingThumbnails = true
            thumbnailTask = Task {
                await RawImageLoader.shared.preloadThumbnails(for: loadedFiles, targetSize: 200)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.isCreatingThumbnails = false
                }
            }
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
        zoomOverlayVisible = true
        zoomTask = Task {
            let image = await RawImageLoader.shared.extractedJPG(for: selectedFile.url)
            guard !Task.isCancelled else { return }
            zoomImage = image
        }
    }

    func closeZoom() {
        zoomTask?.cancel()
        zoomTask = nil
        zoomOverlayVisible = false
        zoomImage = nil
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

    private func startSecurityScopedAccess(for url: URL) -> Bool {
        if activeSecurityScopedURL != url {
            stopActiveSecurityScopedAccess()
        }
        guard url.startAccessingSecurityScopedResource() else { return false }
        activeSecurityScopedURL = url
        return true
    }
}
