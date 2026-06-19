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
    var selectedFileIDs: Set<BrowserFileItem.ID> = []
    var isShowingFolderPicker = false
    var isShowingCopyDestinationPicker = false
    var isShowingClearCatalogConfirmation = false
    var isScanning = false
    var isCreatingThumbnails = false
    var copyProgress = CopyProgress()
    var copyFailure: CopyFailure?
    var deleteProgress = CopyProgress()
    var deleteFailure: CopyFailure?
    var zoomOverlayVisible = false
    var zoomImage: CGImage?
    var zoomExifInfo: BrowserExifInfo?
    var zoomScale: CGFloat = 1.0
    var zoomOffset: CGSize = .zero
    var isZoomMetadataCollapsed = false
    var zoomMetadataOffset: CGSize = .zero
    var isZoomFocusPointVisible = false
    var settings = BrowserSettings()
    private var fileRatings: [CatalogFileRatingKey: Int] = [:]

    var zoomOverlayNavigationAxis: ZoomOverlayNavigationAxis = .horizontal

    @ObservationIgnored private var activeSecurityScopedURL: URL?
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var thumbnailTask: Task<Void, Never>?
    @ObservationIgnored private var zoomTask: Task<Void, Never>?
    @ObservationIgnored private var scanID = UUID()
    @ObservationIgnored private var selectionAnchorFileID: BrowserFileItem.ID?
    @ObservationIgnored private var rememberedCatalogs: [URL: RememberedCatalog] = [:]

    var selectedFile: BrowserFileItem? {
        files.first { $0.id == selectedFileID }
    }

    var selectedFiles: [BrowserFileItem] {
        files.filter { selectedFileIDs.contains($0.id) }
    }

    var selectedFileCount: Int {
        selectedFileIDs.count
    }

    var canCopySelectedFiles: Bool {
        !selectedFileIDs.isEmpty && !copyProgress.isActive
    }

    var rejectedFileCount: Int {
        ratedFiles(matching: .rejected).count
    }

    var positiveRatedFileCount: Int {
        ratedFiles(matching: .positive).count
    }

    var canDeleteRejectedFiles: Bool {
        rejectedFileCount > 0 && !copyProgress.isActive && !deleteProgress.isActive
    }

    var canCopyRatedFiles: Bool {
        positiveRatedFileCount > 0 && !copyProgress.isActive && !deleteProgress.isActive
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

    func loadRememberedCatalogs() async {
        let catalogs = await RememberedCatalogStore.load()
        var loadedCatalogs: [URL: RememberedCatalog] = [:]
        var loadedFolders: [BrowserFolderItem] = []

        for catalog in catalogs {
            guard let url = RememberedCatalogStore.resolvedURL(for: catalog) else { continue }
            let standardizedURL = url.standardizedFileURL
            loadedCatalogs[standardizedURL] = catalog
            loadedFolders.append(BrowserFolderItem(url: standardizedURL))
        }

        rememberedCatalogs = loadedCatalogs
        rootFolders = uniqueFolders(loadedFolders)
        await saveRememberedCatalogs()
        loadSavedRatings()
    }

    func addRootFolder(_ url: URL) {
        let standardizedURL = url.standardizedFileURL
        guard startSecurityScopedAccess(for: standardizedURL) else { return }
        let folder = BrowserFolderItem(url: standardizedURL)
        if !rootFolders.contains(where: { $0.url == standardizedURL }) {
            rootFolders.append(folder)
        }
        rememberCatalog(at: standardizedURL)
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
        selectedFileIDs = []
        selectionAnchorFileID = nil
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
            selectedFileIDs = Set(loadedFiles.first.map { [$0.id] } ?? [])
            selectionAnchorFileID = loadedFiles.first?.id
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
        selectOnlyFile(file)
    }

    func selectOnlyFile(_ file: BrowserFileItem) {
        selectedFileID = file.id
        selectedFileIDs = [file.id]
        selectionAnchorFileID = file.id
    }

    func toggleFileSelection(_ file: BrowserFileItem) {
        if selectedFileIDs.contains(file.id) {
            selectedFileIDs.remove(file.id)
            if selectedFileID == file.id {
                selectedFileID = selectedFiles.first?.id
            }
        } else {
            selectedFileIDs.insert(file.id)
            selectedFileID = file.id
            selectionAnchorFileID = file.id
        }

        if selectedFileIDs.isEmpty {
            selectedFileID = nil
            selectionAnchorFileID = nil
        }
    }

    func extendFileSelection(to file: BrowserFileItem) {
        guard let anchorID = selectionAnchorFileID ?? selectedFileID,
              let anchorIndex = files.firstIndex(where: { $0.id == anchorID }),
              let targetIndex = files.firstIndex(of: file)
        else {
            selectOnlyFile(file)
            return
        }

        let bounds = min(anchorIndex, targetIndex) ... max(anchorIndex, targetIndex)
        selectedFileIDs = Set(files[bounds].map(\.id))
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
        selectedFileIDs = [files[nextIndex].id]
        selectionAnchorFileID = files[nextIndex].id
        if zoomOverlayVisible {
            openZoom(for: files[nextIndex])
        }
    }

    func rating(for file: BrowserFileItem?) -> Int? {
        guard let file,
              let key = ratingKey(for: file)
        else { return nil }
        return fileRatings[key]
    }

    func ratedFileCount(in folder: BrowserFolderItem) -> Int {
        guard let catalogURL = rootCatalogURL(containing: folder.url) else { return 0 }
        let ratedFileNames = Set(
            fileRatings
                .filter { key, _ in key.catalogURL == catalogURL }
                .map(\.key.fileName),
        )
        guard !ratedFileNames.isEmpty,
              let children = try? FileManager.default.contentsOfDirectory(
                  at: folder.url,
                  includingPropertiesForKeys: [.isRegularFileKey],
                  options: [.skipsHiddenFiles, .skipsPackageDescendants],
              )
        else { return 0 }

        return children.reduce(into: 0) { count, url in
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            if values?.isRegularFile == true, ratedFileNames.contains(url.lastPathComponent) {
                count += 1
            }
        }
    }

    func updateRating(for file: BrowserFileItem, rating: Int) {
        guard let key = ratingKey(for: file) else { return }
        fileRatings[key] = rating
        Task {
            await saveRatings()
        }
    }

    func copySelectedFiles(to destinationURL: URL) async {
        await copyFiles(selectedFiles, to: destinationURL)
    }

    func copyRatedFiles(to destinationURL: URL, filter: RatedCopyFilter) async {
        await copyFiles(ratedFiles(matching: filter), to: destinationURL)
    }

    func deleteRejectedFiles() async {
        guard let selectedFolder else { return }
        let filesToDelete = ratedFiles(matching: .rejected)
        guard !filesToDelete.isEmpty else { return }
        guard startSecurityScopedAccess(for: securityScopedURL(for: selectedFolder.url)) else { return }

        deleteProgress = CopyProgress(completedCount: 0, totalCount: filesToDelete.count)
        deleteFailure = nil

        do {
            for (index, file) in filesToDelete.enumerated() {
                try Task.checkCancellation()
                try await Task.detached(priority: .utility) {
                    try FileManager.default.trashItem(at: file.url, resultingItemURL: nil)
                }.value
                deleteProgress = CopyProgress(completedCount: index + 1, totalCount: filesToDelete.count)
            }

            let deletedIDs = Set(filesToDelete.map(\.id))
            let deletedRatingKeys = Set(filesToDelete.compactMap { ratingKey(for: $0) })
            files.removeAll { deletedIDs.contains($0.id) }
            selectedFileIDs.subtract(deletedIDs)
            if selectedFileID.map(deletedIDs.contains) == true {
                selectedFileID = files.first?.id
            }
            if selectionAnchorFileID.map(deletedIDs.contains) == true {
                selectionAnchorFileID = selectedFileID
            }
            fileRatings = fileRatings.filter { key, _ in !deletedRatingKeys.contains(key) }
            await saveRatings()
        } catch {
            deleteFailure = CopyFailure(message: error.localizedDescription)
        }
    }

    func clearRememberedCatalogs() async {
        scanTask?.cancel()
        thumbnailTask?.cancel()
        closeZoom()
        stopActiveSecurityScopedAccess()

        rootFolders = []
        folderChildren = [:]
        expandedFolderIDs = []
        loadingFolderIDs = []
        files = []
        selectedFolder = nil
        selectedFileID = nil
        selectedFileIDs = []
        selectionAnchorFileID = nil
        rememberedCatalogs = [:]
        fileRatings = [:]
        isScanning = false
        isCreatingThumbnails = false
        await RememberedCatalogStore.clear()
        await WriteSavedFilesJSON.clear()
    }

    func removeRootCatalog(_ folder: BrowserFolderItem) async {
        let catalogURL = folder.url.standardizedFileURL
        let removedSelectedFolder = selectedFolder?.url.standardizedFileURL.isEqualOrDescendant(of: catalogURL) == true

        scanTask?.cancel()
        thumbnailTask?.cancel()
        if removedSelectedFolder {
            closeZoom()
            files = []
            selectedFolder = nil
            selectedFileID = nil
            selectedFileIDs = []
            selectionAnchorFileID = nil
            isScanning = false
            isCreatingThumbnails = false
        }

        rootFolders.removeAll { $0.url.standardizedFileURL == catalogURL }
        folderChildren = folderChildren.filter { key, _ in
            !key.standardizedFileURL.isEqualOrDescendant(of: catalogURL)
        }
        expandedFolderIDs = expandedFolderIDs.filter {
            !$0.standardizedFileURL.isEqualOrDescendant(of: catalogURL)
        }
        loadingFolderIDs = loadingFolderIDs.filter {
            !$0.standardizedFileURL.isEqualOrDescendant(of: catalogURL)
        }
        rememberedCatalogs.removeValue(forKey: catalogURL)
        fileRatings = fileRatings.filter { key, _ in key.catalogURL != catalogURL }
        if activeSecurityScopedURL == catalogURL {
            stopActiveSecurityScopedAccess()
        }

        await saveRememberedCatalogs()
        await saveRatings()
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

    private func rememberCatalog(at url: URL) {
        guard let catalog = RememberedCatalogStore.catalog(for: url) else { return }
        rememberedCatalogs[url.standardizedFileURL] = catalog
        Task {
            await saveRememberedCatalogs()
        }
    }

    private func saveRememberedCatalogs() async {
        let catalogs = rootFolders.compactMap { rememberedCatalogs[$0.url.standardizedFileURL] }
        await RememberedCatalogStore.save(catalogs)
    }

    private func loadSavedRatings() {
        guard !rootFolders.isEmpty,
              let savedFiles = ReadSavedFilesJSON().readjsonfilesavedfiles()
        else { return }

        let rootCatalogURLs = Set(rootFolders.map { $0.url.standardizedFileURL })
        var loadedRatings: [CatalogFileRatingKey: Int] = [:]

        for savedCatalog in savedFiles {
            guard let catalogURL = savedCatalog.catalog?.standardizedFileURL,
                  rootCatalogURLs.contains(catalogURL),
                  let records = savedCatalog.filerecords
            else { continue }

            for record in records {
                guard let fileName = record.fileName,
                      let rating = record.rating
                else { continue }
                loadedRatings[CatalogFileRatingKey(catalogURL: catalogURL, fileName: fileName)] = rating
            }
        }

        fileRatings = loadedRatings
    }

    private func saveRatings() async {
        let savedFiles = rootFolders.compactMap { rootFolder -> SavedFiles? in
            let catalogURL = rootFolder.url.standardizedFileURL
            let records = fileRatings
                .filter { key, _ in key.catalogURL == catalogURL }
                .sorted { lhs, rhs in lhs.key.fileName.localizedStandardCompare(rhs.key.fileName) == .orderedAscending }
                .map { key, rating in
                    FileRecord(
                        fileName: key.fileName,
                        dateTagged: nil,
                        rating: rating,
                    )
                }

            guard !records.isEmpty else { return nil }
            return SavedFiles(
                catalog: catalogURL,
                dateStart: nil,
                filerecords: records,
            )
        }

        if savedFiles.isEmpty {
            await WriteSavedFilesJSON.clear()
        } else {
            await WriteSavedFilesJSON.write(savedFiles)
        }
    }

    private func copyFiles(_ filesToCopy: [BrowserFileItem], to destinationURL: URL) async {
        guard !filesToCopy.isEmpty else { return }

        let destination = destinationURL.standardizedFileURL
        let didAccessDestination = destination.startAccessingSecurityScopedResource()
        defer {
            if didAccessDestination {
                destination.stopAccessingSecurityScopedResource()
            }
        }

        copyProgress = CopyProgress(completedCount: 0, totalCount: filesToCopy.count)
        copyFailure = nil

        do {
            for (index, file) in filesToCopy.enumerated() {
                try Task.checkCancellation()
                let targetURL = uniqueDestinationURL(for: file.url.lastPathComponent, in: destination)
                try await Task.detached(priority: .utility) {
                    try FileManager.default.copyItem(at: file.url, to: targetURL)
                }.value
                copyProgress = CopyProgress(completedCount: index + 1, totalCount: filesToCopy.count)
            }
        } catch {
            copyFailure = CopyFailure(message: error.localizedDescription)
        }
    }

    private func ratedFiles(matching filter: RatedCopyFilter) -> [BrowserFileItem] {
        files.filter { file in
            guard let rating = rating(for: file) else { return false }
            return filter.includes(rating)
        }
    }

    private func ratingKey(for file: BrowserFileItem) -> CatalogFileRatingKey? {
        guard let catalogURL = rootCatalogURL(containing: file.url) else { return nil }
        return CatalogFileRatingKey(
            catalogURL: catalogURL,
            fileName: file.url.lastPathComponent,
        )
    }

    private func rootCatalogURL(containing fileURL: URL) -> URL? {
        let standardizedFileURL = fileURL.standardizedFileURL
        return rootFolders
            .map(\.url)
            .map(\.standardizedFileURL)
            .filter { standardizedFileURL.isEqualOrDescendant(of: $0) }
            .max { first, second in
                first.pathComponents.count < second.pathComponents.count
            }
    }

    private func uniqueFolders(_ folders: [BrowserFolderItem]) -> [BrowserFolderItem] {
        var seen: Set<URL> = []
        return folders
            .filter { folder in
                guard !seen.contains(folder.url) else { return false }
                seen.insert(folder.url)
                return true
            }
    }

    private func uniqueDestinationURL(for fileName: String, in destination: URL) -> URL {
        let proposedURL = destination.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: proposedURL.path) else {
            return proposedURL
        }

        let sourceURL = URL(fileURLWithPath: fileName)
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let pathExtension = sourceURL.pathExtension

        for copyIndex in 1 ... 10000 {
            let suffix = copyIndex == 1 ? " copy" : " copy \(copyIndex)"
            let duplicateName = pathExtension.isEmpty
                ? "\(baseName)\(suffix)"
                : "\(baseName)\(suffix).\(pathExtension)"
            let duplicateURL = destination.appendingPathComponent(duplicateName)
            if !FileManager.default.fileExists(atPath: duplicateURL.path) {
                return duplicateURL
            }
        }

        let fallbackName = pathExtension.isEmpty
            ? "\(baseName) copy \(UUID().uuidString)"
            : "\(baseName) copy \(UUID().uuidString).\(pathExtension)"
        return destination.appendingPathComponent(fallbackName)
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

enum RatedCopyFilter: Hashable, Identifiable {
    case positive
    case rating(Int)
    case rejected

    var id: String {
        switch self {
        case .positive:
            "positive"

        case let .rating(rating):
            "rating-\(rating)"

        case .rejected:
            "rejected"
        }
    }

    var title: String {
        switch self {
        case .positive:
            "Rated 2-5"

        case let .rating(rating):
            "Rated \(rating)"

        case .rejected:
            "Rejected"
        }
    }

    func includes(_ rating: Int) -> Bool {
        switch self {
        case .positive:
            (2 ... 5).contains(rating)

        case let .rating(targetRating):
            rating == targetRating

        case .rejected:
            rating == -1
        }
    }
}

private struct CatalogFileRatingKey: Hashable {
    let catalogURL: URL
    let fileName: String
}

private extension URL {
    func isEqualOrDescendant(of ancestorURL: URL) -> Bool {
        let pathComponents = standardizedFileURL.pathComponents
        let ancestorPathComponents = ancestorURL.standardizedFileURL.pathComponents

        guard pathComponents.count >= ancestorPathComponents.count else { return false }
        return zip(pathComponents, ancestorPathComponents).allSatisfy(==)
    }
}
