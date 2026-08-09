import CoreAICLIPBackend
import CoreGraphics
import Foundation
import Observation
import RawParserKit

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
    var zoomExifInfo: RawImageMetadata?
    var isZoomExifInfoLoaded = false
    var zoomScale: CGFloat = 1.0
    var zoomOffset: CGSize = .zero
    var isZoomMetadataCollapsed = false
    var zoomMetadataOffset: CGSize = .zero
    var isZoomFocusPointVisible = false
    var zoomLaunchContext: BrowserZoomLaunchContext = .default
    var settings = BrowserSettings()
    var clipModelStatus: CLIPModelStatus = .notConfigured
    var clipIndexStatus: CLIPIndexStatus = .noFolderSelected
    var isIndexing = false
    var indexingProgress: CLIPIndexingProgress?
    var lastIndexSummary: CLIPIndexSummary?
    var semanticSearchQuery = ""
    var semanticSearchResults: [CLIPSearchResult] = []
    var semanticSearchActive = false
    var isSearching = false
    var isRunningSemanticTest = false
    var semanticTestProgress: SemanticSearchTestProgress?
    var semanticTestOutcome: SemanticSearchTestOutcome?
    var hasCompatibleCLIPIndex = false
    var clipFeatureError: String?
    private var fileRatings: [CatalogFileRatingKey: Int] = [:]

    var zoomOverlayNavigationAxis: ZoomOverlayNavigationAxis = .horizontal

    @ObservationIgnored private var activeSecurityScopedURL: URL?
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var thumbnailTask: Task<Void, Never>?
    @ObservationIgnored private var zoomTask: Task<Void, Never>?
    @ObservationIgnored private var scanID = UUID()
    @ObservationIgnored private var selectionAnchorFileID: BrowserFileItem.ID?
    @ObservationIgnored private var rememberedCatalogs: [URL: RememberedCatalog] = [:]
    @ObservationIgnored private let clipModelManager = CLIPModelManager()
    @ObservationIgnored private var clipProvider: CoreAICLIPProvider?
    @ObservationIgnored private var clipEngine: CLIPSearchEngine?
    @ObservationIgnored private var clipEngineDirectoryURL: URL?
    @ObservationIgnored private var modelValidationTask: Task<Void, Never>?
    @ObservationIgnored private var indexingTask: Task<Void, Never>?
    @ObservationIgnored private var indexValidationTask: Task<Void, Never>?
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var semanticTestTask: Task<Void, Never>?
    @ObservationIgnored private var semanticFiles: [BrowserFileItem] = []
    @ObservationIgnored private var indexingID = UUID()
    @ObservationIgnored private var indexValidationID = UUID()
    @ObservationIgnored private var searchID = UUID()
    @ObservationIgnored private var semanticTestID = UUID()

    var displayedFiles: [BrowserFileItem] {
        semanticSearchActive ? semanticFiles : files
    }

    var isShowingSemanticResults: Bool {
        semanticSearchActive
    }

    var clipModelPath: String? { settings.clipModelPath }
    var semanticSearchLimit: Int { settings.semanticSearchLimit }

    var canIndexSelectedFolder: Bool {
        selectedFolder != nil
            && clipProvider != nil
            && !isIndexing
            && !isSearching
            && !isRunningSemanticTest
    }

    var canSearch: Bool {
        hasCompatibleCLIPIndex
            && clipEngine != nil
            && !isIndexing
            && !isSearching
            && !isRunningSemanticTest
    }

    var canRunSemanticTest: Bool {
        hasCompatibleCLIPIndex
            && clipEngine != nil
            && selectedFolder != nil
            && !isIndexing
            && !isSearching
            && !isRunningSemanticTest
    }

    var selectedFile: BrowserFileItem? {
        displayedFiles.first { $0.id == selectedFileID }
    }

    var selectedFiles: [BrowserFileItem] {
        displayedFiles.filter { selectedFileIDs.contains($0.id) }
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
        !isCreatingThumbnails && !isIndexing
    }

    var title: String {
        guard let selectedFolder else { return "RawCullFB" }
        if isShowingSemanticResults {
            return "Semantic Search (\(semanticSearchResults.count) results)"
        }
        return "\(selectedFolder.name) (\(files.count) files)"
    }

    func loadSettings() async {
        settings = await BrowserSettingsStore.load()
        await MemoryImageCache.shared.apply(settings: settings)
        if let path = settings.clipModelPath {
            validateCLIPModel(at: URL(filePath: path))
        }
    }

    func setCLIPModelURL(_ url: URL) {
        let standardizedURL = url.standardizedFileURL
        settings.clipModelPath = standardizedURL.path
        persistSettings()
        validateCLIPModel(at: standardizedURL)
    }

    func clearCLIPModel() {
        modelValidationTask?.cancel()
        indexingTask?.cancel()
        indexValidationTask?.cancel()
        searchTask?.cancel()
        semanticTestTask?.cancel()
        indexingID = UUID()
        indexValidationID = UUID()
        semanticTestID = UUID()
        settings.clipModelPath = nil
        settings.lastIndexedDirectoryPath = nil
        clipModelStatus = .notConfigured
        clipProvider = nil
        clipEngine = nil
        clipEngineDirectoryURL = nil
        hasCompatibleCLIPIndex = false
        clipIndexStatus = selectedFolder == nil ? .noFolderSelected : .modelRequired
        isIndexing = false
        isSearching = false
        isRunningSemanticTest = false
        semanticTestProgress = nil
        clearSemanticSearchResults()
        persistSettings()
    }

    func adjustSemanticSearchLimit(by delta: Int) {
        let adjusted = min(max(settings.semanticSearchLimit + delta, 10), 500)
        guard adjusted != settings.semanticSearchLimit else { return }
        settings.semanticSearchLimit = adjusted
        persistSettings()
        if !semanticSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           hasCompatibleCLIPIndex
        {
            startSemanticSearch()
        }
    }

    func startIndexingSelectedFolder() {
        guard let directory = selectedFolder?.url.standardizedFileURL,
              let provider = clipProvider
        else {
            clipFeatureError = CLIPFeatureError.modelNotConfigured.description
            return
        }

        indexingTask?.cancel()
        indexValidationTask?.cancel()
        searchTask?.cancel()
        let operationID = UUID()
        indexingID = operationID
        indexValidationID = UUID()
        let engine = makeCLIPEngine(provider: provider, directory: directory)
        clipEngine = engine
        clipEngineDirectoryURL = directory
        hasCompatibleCLIPIndex = false
        clipIndexStatus = .checking(directory)
        isIndexing = true
        indexingProgress = nil
        lastIndexSummary = nil
        clipFeatureError = nil
        clearSemanticSearchResults(keepingQuery: true)

        indexingTask = Task { [weak self] in
            guard let self else { return }
            do {
                let summary = try await engine.synchronize(directory: directory) { [weak self] progress in
                    await self?.publishIndexingProgress(progress, operationID: operationID)
                }
                try Task.checkCancellation()
                guard self.indexingID == operationID, self.clipEngineDirectoryURL == directory else { return }
                self.lastIndexSummary = summary
                self.settings.lastIndexedDirectoryPath = directory.path
                self.persistSettings()
            } catch is CancellationError {
                // Cancellation is user initiated or caused by a replacement index operation.
            } catch {
                guard !Task.isCancelled, self.indexingID == operationID else { return }
                self.clipFeatureError = String(describing: error)
            }
            guard self.indexingID == operationID, self.clipEngineDirectoryURL == directory else { return }
            self.isIndexing = false
            self.indexingProgress = nil
            self.indexingTask = nil
            self.validateSelectedFolderCLIPIndex()
        }
    }

    func cancelIndexing() {
        indexingID = UUID()
        indexingTask?.cancel()
        indexingTask = nil
        isIndexing = false
        indexingProgress = nil
        validateSelectedFolderCLIPIndex()
    }

    func validateSelectedFolderCLIPIndex() {
        indexValidationTask?.cancel()
        let validationID = UUID()
        indexValidationID = validationID

        guard let directory = selectedFolder?.url.standardizedFileURL else {
            clipIndexStatus = .noFolderSelected
            hasCompatibleCLIPIndex = false
            return
        }
        guard let provider = clipProvider else {
            clipIndexStatus = .modelRequired
            hasCompatibleCLIPIndex = false
            return
        }

        let engine = makeCLIPEngine(provider: provider, directory: directory)
        clipEngine = engine
        clipEngineDirectoryURL = directory
        clipIndexStatus = .checking(directory)
        hasCompatibleCLIPIndex = false

        indexValidationTask = Task { [weak self] in
            guard let self else { return }
            let status = await engine.validateIndex(directory: directory)
            guard !Task.isCancelled,
                  self.indexValidationID == validationID,
                  self.selectedFolder?.url.standardizedFileURL == directory
            else { return }
            self.clipIndexStatus = status
            self.hasCompatibleCLIPIndex = status.allowsSearch
            if status.allowsSearch {
                self.settings.lastIndexedDirectoryPath = directory.path
                self.persistSettings()
            } else {
                self.clearSemanticSearchResults()
            }
            self.indexValidationTask = nil
        }
    }

    func startSemanticSearch() {
        guard !isRunningSemanticTest else { return }
        let query = semanticSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            clearSemanticSearchResults()
            return
        }
        guard let engine = clipEngine, hasCompatibleCLIPIndex else {
            clipFeatureError = CLIPFeatureError.missingCompatibleIndex.description
            return
        }

        searchTask?.cancel()
        let operationID = UUID()
        searchID = operationID
        isSearching = true
        clipFeatureError = nil
        semanticSearchActive = true
        semanticSearchResults = []
        semanticFiles = []
        let limit = settings.semanticSearchLimit
        searchTask = Task { [weak self] in
            guard let self else { return }
            do {
                let results = try await engine.search(text: query, limit: limit)
                try Task.checkCancellation()
                guard self.searchID == operationID,
                      self.semanticSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines) == query
                else { return }
                self.semanticSearchResults = results
                self.semanticFiles = results.map { BrowserFileItem(url: $0.url) }
                self.selectedFileID = self.semanticFiles.first?.id
                self.selectedFileIDs = Set(self.semanticFiles.first.map { [$0.id] } ?? [])
                self.selectionAnchorFileID = self.semanticFiles.first?.id
            } catch is CancellationError {
                // A newer query owns result publication.
            } catch {
                guard !Task.isCancelled, self.searchID == operationID else { return }
                self.clipFeatureError = String(describing: error)
            }
            guard self.searchID == operationID else { return }
            self.isSearching = false
            self.searchTask = nil
        }
    }

    func startSemanticTest() {
        guard let directory = selectedFolder?.url.standardizedFileURL,
              let engine = clipEngine,
              hasCompatibleCLIPIndex
        else {
            clipFeatureError = CLIPFeatureError.missingCompatibleIndex.description
            return
        }
        guard case let .available(_, fingerprint, modelName) = clipModelStatus else {
            clipFeatureError = CLIPFeatureError.modelNotConfigured.description
            return
        }

        semanticTestTask?.cancel()
        searchTask?.cancel()
        searchTask = nil
        searchID = UUID()
        isSearching = false

        let operationID = UUID()
        let limit = settings.semanticSearchLimit
        semanticTestID = operationID
        isRunningSemanticTest = true
        semanticTestProgress = nil
        semanticTestOutcome = nil
        clipFeatureError = nil

        semanticTestTask = Task { [weak self] in
            guard let self else { return }
            do {
                let outcome = try await SemanticSearchTestRunner.run(
                    directory: directory,
                    modelName: modelName,
                    modelFingerprint: fingerprint,
                    resultLimit: limit,
                    search: { [weak self] query, resultLimit in
                        let results = try await engine.search(
                            text: query,
                            limit: resultLimit,
                        )
                        await self?.publishSemanticTestResults(
                            query: query,
                            results: results,
                            operationID: operationID,
                        )
                        return results
                    },
                    similarity: { neighborLimit in
                        try await engine.evaluateImageSimilarity(
                            neighborLimit: neighborLimit,
                        )
                    },
                    progress: { [weak self] progress in
                        await self?.publishSemanticTestProgress(
                            progress,
                            operationID: operationID,
                        )
                    },
                )
                guard self.semanticTestID == operationID else { return }
                self.semanticTestOutcome = outcome
            } catch is CancellationError {
                // The runner writes its last completed query before cancellation.
            } catch {
                guard self.semanticTestID == operationID else { return }
                self.clipFeatureError = error.localizedDescription
            }

            guard self.semanticTestID == operationID else { return }
            self.isRunningSemanticTest = false
            self.semanticTestProgress = nil
            self.semanticTestTask = nil
        }
    }

    func cancelSemanticTest() {
        semanticTestID = UUID()
        semanticTestTask?.cancel()
        semanticTestTask = nil
        isRunningSemanticTest = false
        semanticTestProgress = nil
    }

    func clearSemanticSearchResults(keepingQuery: Bool = false) {
        searchID = UUID()
        searchTask?.cancel()
        searchTask = nil
        isSearching = false
        semanticSearchResults = []
        semanticSearchActive = false
        semanticFiles = []
        if !keepingQuery {
            semanticSearchQuery = ""
        }
        selectedFileID = files.first?.id
        selectedFileIDs = Set(files.first.map { [$0.id] } ?? [])
        selectionAnchorFileID = files.first?.id
    }

    private func publishSemanticTestProgress(
        _ progress: SemanticSearchTestProgress,
        operationID: UUID,
    ) {
        guard semanticTestID == operationID else { return }
        semanticTestProgress = progress
        if let query = progress.currentQuery {
            semanticSearchQuery = query
        }
    }

    private func publishSemanticTestResults(
        query: String,
        results: [CLIPSearchResult],
        operationID: UUID,
    ) {
        guard semanticTestID == operationID else { return }
        semanticSearchQuery = query
        semanticSearchActive = true
        semanticSearchResults = results
        semanticFiles = results.map { BrowserFileItem(url: $0.url) }
        selectedFileID = semanticFiles.first?.id
        selectedFileIDs = Set(semanticFiles.first.map { [$0.id] } ?? [])
        selectionAnchorFileID = semanticFiles.first?.id
    }

    func setRatingPinsEnabled(_ isEnabled: Bool) {
        guard settings.enableRatingPins != isEnabled else { return }
        settings.enableRatingPins = isEnabled
        let updatedSettings = settings
        Task {
            await BrowserSettingsStore.save(updatedSettings)
        }
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
        await loadChildren(for: rootFolders)
    }

    func addRootFolder(_ url: URL) {
        let standardizedURL = url.standardizedFileURL
        guard startSecurityScopedAccess(for: standardizedURL) else { return }
        let folder = BrowserFolderItem(url: standardizedURL)
        if !rootFolders.contains(where: { $0.url == standardizedURL }) {
            rootFolders.append(folder)
            Task {
                await loadChildren(for: [folder])
            }
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
        clearSemanticSearchResults()
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
            setLoadedChildren(loadedFolders, for: folder)
            files = loadedFiles
            selectedFileID = loadedFiles.first?.id
            selectedFileIDs = Set(loadedFiles.first.map { [$0.id] } ?? [])
            selectionAnchorFileID = loadedFiles.first?.id
            isScanning = false
        }
        validateSelectedFolderCLIPIndex()
    }

    private func loadChildrenIfNeeded(for folder: BrowserFolderItem) {
        Task {
            await loadChildren(for: [folder])
        }
    }

    private func loadChildren(for folders: [BrowserFolderItem]) async {
        for folder in folders where folderChildren[folder.id] == nil && !loadingFolderIDs.contains(folder.id) {
            guard startSecurityScopedAccess(for: securityScopedURL(for: folder.url)) else { continue }
            loadingFolderIDs.insert(folder.id)
            let loadedFolders = await RawImageLoader.shared.discoverFolders(at: folder.url)
            guard !Task.isCancelled else {
                loadingFolderIDs.remove(folder.id)
                return
            }
            setLoadedChildren(loadedFolders, for: folder)
            loadingFolderIDs.remove(folder.id)
        }
    }

    private func setLoadedChildren(_ children: [BrowserFolderItem], for folder: BrowserFolderItem) {
        folderChildren[folder.id] = children
        if rootFolders.contains(where: { $0.id == folder.id }), !children.isEmpty {
            expandedFolderIDs.insert(folder.id)
        }
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
              let anchorIndex = displayedFiles.firstIndex(where: { $0.id == anchorID }),
              let targetIndex = displayedFiles.firstIndex(of: file)
        else {
            selectOnlyFile(file)
            return
        }

        let bounds = min(anchorIndex, targetIndex) ... max(anchorIndex, targetIndex)
        selectedFileIDs = Set(displayedFiles[bounds].map(\.id))
        selectedFileID = file.id
    }

    func openZoom(
        for file: BrowserFileItem? = nil,
        initialZoomMode: BrowserZoomInitialMode = .fit,
        showFocusPointOnOpen: Bool = false,
    ) {
        if let file {
            selectedFileID = file.id
        }
        guard let selectedFile else { return }

        zoomTask?.cancel()
        zoomImage = nil
        zoomExifInfo = nil
        isZoomExifInfoLoaded = false
        zoomLaunchContext = BrowserZoomLaunchContext(
            initialZoomMode: initialZoomMode,
            showFocusPointOnOpen: showFocusPointOnOpen,
        )
        zoomOverlayVisible = true
        let previewSize = settings.thumbnailSizeFullSize
        zoomTask = Task {
            async let image = RawImageLoader.shared.previewImage(
                for: selectedFile.url,
                maxPixelSize: previewSize,
            )
            async let exifInfo = RawImageLoader.shared.metadata(for: selectedFile.url)
            let (loadedImage, loadedExifInfo) = await (image, exifInfo)
            guard !Task.isCancelled else { return }
            zoomImage = loadedImage
            zoomExifInfo = loadedExifInfo
            isZoomExifInfoLoaded = true
        }
    }

    func closeZoom() {
        zoomTask?.cancel()
        zoomTask = nil
        zoomOverlayVisible = false
        zoomImage = nil
        zoomExifInfo = nil
        isZoomExifInfoLoaded = false
        zoomLaunchContext = .default
        // Abandon any in-flight full-size decode: it's no longer needed and
        // should not keep consuming memory in the background.
        Task { await RawImageLoader.shared.cancelPreview() }
    }

    func resetZoomInterfaceState() {
        zoomScale = 1.0
        zoomOffset = .zero
        isZoomExifInfoLoaded = false
        isZoomMetadataCollapsed = false
        zoomMetadataOffset = .zero
        isZoomFocusPointVisible = false
        zoomLaunchContext = .default
    }

    func navigateSelection(by delta: Int) {
        guard let selectedFile,
              let currentIndex = displayedFiles.firstIndex(of: selectedFile)
        else { return }

        let nextIndex = currentIndex + delta
        guard displayedFiles.indices.contains(nextIndex) else { return }
        selectedFileID = displayedFiles[nextIndex].id
        selectedFileIDs = [displayedFiles[nextIndex].id]
        selectionAnchorFileID = displayedFiles[nextIndex].id
        if zoomOverlayVisible {
            openZoom(
                for: displayedFiles[nextIndex],
                initialZoomMode: zoomLaunchContext.initialZoomMode,
                showFocusPointOnOpen: zoomLaunchContext.showFocusPointOnOpen,
            )
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

    func updateSelectedFilesRatingAndAdvance(_ rating: Int) -> Bool {
        guard settings.enableRatingPins else { return false }
        let filesToRate = selectedFiles.isEmpty ? selectedFile.map { [$0] } ?? [] : selectedFiles
        guard !filesToRate.isEmpty else { return false }

        for file in filesToRate {
            setRating(rating, for: file)
        }

        Task {
            await saveRatings()
        }
        navigateSelection(by: 1)
        return true
    }

    private func setRating(_ rating: Int, for file: BrowserFileItem) {
        guard let key = ratingKey(for: file) else { return }
        fileRatings[key] = rating
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
        resetCLIPIndexSelection()
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
            resetCLIPIndexSelection()
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
        return true
    }

    private func validateCLIPModel(at url: URL) {
        modelValidationTask?.cancel()
        indexingTask?.cancel()
        indexValidationTask?.cancel()
        searchTask?.cancel()
        semanticTestTask?.cancel()
        indexingID = UUID()
        indexValidationID = UUID()
        searchID = UUID()
        semanticTestID = UUID()
        clipModelStatus = .checking(url)
        clipProvider = nil
        clipEngine = nil
        clipEngineDirectoryURL = nil
        hasCompatibleCLIPIndex = false
        clipIndexStatus = selectedFolder == nil ? .noFolderSelected : .modelRequired
        isIndexing = false
        isSearching = false
        isRunningSemanticTest = false
        semanticTestProgress = nil
        clipFeatureError = nil
        clearSemanticSearchResults()

        modelValidationTask = Task { [weak self] in
            guard let self else { return }
            let load = await self.clipModelManager.load(url: url)
            guard !Task.isCancelled, self.settings.clipModelPath == url.path else { return }
            self.clipModelStatus = load.status
            self.clipProvider = load.provider
            if self.selectedFolder != nil {
                self.validateSelectedFolderCLIPIndex()
            } else if let provider = load.provider,
               let directoryPath = self.settings.lastIndexedDirectoryPath
            {
                await self.restoreCLIPEngine(
                    provider: provider,
                    directory: URL(filePath: directoryPath),
                )
            }
            self.modelValidationTask = nil
        }
    }

    private func restoreCLIPEngine(
        provider: CoreAICLIPProvider,
        directory: URL,
    ) async {
        let standardizedDirectory = directory.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: standardizedDirectory.path,
            isDirectory: &isDirectory,
        ), isDirectory.boolValue else { return }
        let engine = makeCLIPEngine(provider: provider, directory: standardizedDirectory)
        guard await engine.hasCompatibleIndex() else { return }
        clipEngine = engine
        clipEngineDirectoryURL = standardizedDirectory
        let status = await engine.validateIndex(directory: standardizedDirectory)
        clipIndexStatus = status
        hasCompatibleCLIPIndex = status.allowsSearch
    }

    private func makeCLIPEngine(
        provider: CoreAICLIPProvider,
        directory: URL,
    ) -> CLIPSearchEngine {
        let indexURL = CLIPIndexPaths.defaultIndexURL(
            directory: directory,
            modelFingerprint: provider.backendDescriptor.modelFingerprint,
        )
        return CLIPSearchEngine(
            provider: provider,
            indexStore: CLIPIndexStore(fileURL: indexURL),
            concurrencyLimit: 2,
        )
    }

    private func publishIndexingProgress(
        _ progress: CLIPIndexingProgress,
        operationID: UUID,
    ) {
        guard indexingID == operationID else { return }
        indexingProgress = progress
    }

    private func resetCLIPIndexSelection() {
        indexingTask?.cancel()
        indexValidationTask?.cancel()
        searchTask?.cancel()
        semanticTestTask?.cancel()
        indexingID = UUID()
        indexValidationID = UUID()
        searchID = UUID()
        semanticTestID = UUID()
        clipEngine = nil
        clipEngineDirectoryURL = nil
        clipIndexStatus = .noFolderSelected
        hasCompatibleCLIPIndex = false
        isIndexing = false
        isRunningSemanticTest = false
        indexingProgress = nil
        semanticTestProgress = nil
        clearSemanticSearchResults()
    }

    private func persistSettings() {
        let updatedSettings = settings
        Task {
            await BrowserSettingsStore.save(updatedSettings)
        }
    }
}
