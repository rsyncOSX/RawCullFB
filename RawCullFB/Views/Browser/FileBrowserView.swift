import SwiftUI

struct FileBrowserView: View {
    @Bindable var viewModel: FileBrowserViewModel
    @State private var folderPickerPurpose: FolderPickerPurpose?
    @State private var isShowingDeleteRejectedConfirmation = false

    var body: some View {
        ZStack {
            NavigationSplitView {
                BrowserSidebarView(viewModel: viewModel)
            } detail: {
                BrowserGridView(viewModel: viewModel)
                    .navigationTitle(viewModel.title)
                    .toolbar { toolbarContent }
            }

            if viewModel.zoomOverlayVisible {
                BrowserZoomOverlayView(viewModel: viewModel)
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .fileImporter(isPresented: folderPickerBinding, allowedContentTypes: [.folder]) { result in
            let purpose = folderPickerPurpose ?? .addRootFolder
            folderPickerPurpose = nil
            guard let url = try? result.get() else { return }

            switch purpose {
            case .addRootFolder:
                viewModel.addRootFolder(url)

            case let .copyRated(filter):
                Task {
                    await viewModel.copyRatedFiles(to: url, filter: filter)
                }
            }
        }
        .onChange(of: viewModel.isShowingFolderPicker) { _, isShowing in
            if isShowing {
                folderPickerPurpose = .addRootFolder
            }
        }
        .onChange(of: viewModel.isShowingCopyDestinationPicker) { _, isShowing in
            if isShowing, folderPickerPurpose == nil {
                folderPickerPurpose = .copyRated(.positive)
            }
        }
        .confirmationDialog(
            "Delete rejected images?",
            isPresented: $isShowingDeleteRejectedConfirmation,
        ) {
            Button("Move Rejected Images to Trash", role: .destructive) {
                Task {
                    await viewModel.deleteRejectedFiles()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This moves \(viewModel.rejectedFileCount) rejected image\(viewModel.rejectedFileCount == 1 ? "" : "s") from the current folder to the Trash.")
        }
        .alert("Copy Failed", isPresented: copyFailureBinding) {
            Button("OK") {
                viewModel.copyFailure = nil
            }
        } message: {
            Text(viewModel.copyFailure?.message ?? "The rated files could not be copied.")
        }
        .alert("Delete Failed", isPresented: deleteFailureBinding) {
            Button("OK") {
                viewModel.deleteFailure = nil
            }
        } message: {
            Text(viewModel.deleteFailure?.message ?? "The rejected files could not be moved to the Trash.")
        }
        .alert("CLIP Operation Failed", isPresented: clipFailureBinding) {
            Button("OK") {
                viewModel.clipFeatureError = nil
            }
        } message: {
            Text(viewModel.clipFeatureError ?? "The CLIP operation could not be completed.")
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                folderPickerPurpose = .addRootFolder
                viewModel.isShowingFolderPicker = true
            } label: {
                Label("Add Folder", systemImage: "folder.badge.plus")
            }
            .help("Add a folder to the sidebar")
        }

        ToolbarItemGroup {
            TextField("Semantic search", text: $viewModel.semanticSearchQuery)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 180, idealWidth: 260, maxWidth: 340)
                .disabled(!viewModel.hasCompatibleCLIPIndex || viewModel.isIndexing)
                .onSubmit {
                    viewModel.startSemanticSearch()
                }

            Button {
                viewModel.startSemanticSearch()
            } label: {
                Label("Search", systemImage: "sparkle.magnifyingglass")
            }
            .disabled(!viewModel.canSearch || viewModel.semanticSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help("Search the CLIP index and show up to \(viewModel.semanticSearchLimit) results")

            Button {
                viewModel.adjustSemanticSearchLimit(by: -10)
            } label: {
                Label("Decrease Results by 10", systemImage: "minus")
            }
            .labelStyle(.iconOnly)
            .disabled(viewModel.semanticSearchLimit <= 10)
            .help("Decrease the semantic result limit by 10")

            Text(viewModel.semanticSearchLimit, format: .number)
                .monospacedDigit()
                .frame(minWidth: 28)
                .help("Maximum semantic search results")

            Button {
                viewModel.adjustSemanticSearchLimit(by: 10)
            } label: {
                Label("Increase Results by 10", systemImage: "plus")
            }
            .labelStyle(.iconOnly)
            .disabled(viewModel.semanticSearchLimit >= 500)
            .help("Increase the semantic result limit by 10")

            if viewModel.isShowingSemanticResults {
                Button {
                    viewModel.clearSemanticSearchResults()
                } label: {
                    Label("Clear Search", systemImage: "xmark.circle")
                }
                .help("Clear semantic search results")
            }

            Button(role: .destructive) {
                isShowingDeleteRejectedConfirmation = true
            } label: {
                Label("Delete Rejected Images", systemImage: "trash")
            }
            .disabled(!viewModel.canDeleteRejectedFiles)
            .help(deleteRejectedButtonHelp)

            Menu {
                Button("Copy Rated 2-5") {
                    showCopyDestinationPicker(for: .positive)
                }
                Divider()
                ForEach([2, 3, 4, 5], id: \.self) { rating in
                    Button("Copy Rated \(rating)") {
                        showCopyDestinationPicker(for: .rating(rating))
                    }
                }
            } label: {
                Label("Copy Rated Images", systemImage: "square.and.arrow.down")
            }
            .disabled(!viewModel.canCopyRatedFiles)
            .help(copyRatedButtonHelp)

            if viewModel.isScanning {
                ProgressView()
                    .controlSize(.small)
                    .help("Discovering supported files")
            } else if viewModel.isCreatingThumbnails {
                ProgressView()
                    .controlSize(.small)
                    .help("Creating 200px memory thumbnails")
            } else if viewModel.isSearching {
                ProgressView()
                    .controlSize(.small)
                    .help("Searching the CLIP index")
            } else if viewModel.copyProgress.isActive {
                ProgressView()
                    .controlSize(.small)
                    .help("Copying \(viewModel.copyProgress.completedCount) of \(viewModel.copyProgress.totalCount) files")
            } else if viewModel.deleteProgress.isActive {
                ProgressView()
                    .controlSize(.small)
                    .help("Deleting \(viewModel.deleteProgress.completedCount) of \(viewModel.deleteProgress.totalCount) files")
            }
        }
    }

    private var folderPickerBinding: Binding<Bool> {
        Binding {
            viewModel.isShowingFolderPicker || viewModel.isShowingCopyDestinationPicker
        } set: { isPresented in
            if !isPresented {
                viewModel.isShowingFolderPicker = false
                viewModel.isShowingCopyDestinationPicker = false
            }
        }
    }

    private func showCopyDestinationPicker(for filter: RatedCopyFilter) {
        folderPickerPurpose = .copyRated(filter)
        viewModel.isShowingCopyDestinationPicker = true
    }

    private var deleteRejectedButtonHelp: String {
        if viewModel.rejectedFileCount == 0 {
            return "No rejected images in the current folder"
        }
        return "Move \(viewModel.rejectedFileCount) rejected image\(viewModel.rejectedFileCount == 1 ? "" : "s") to the Trash"
    }

    private var copyRatedButtonHelp: String {
        if viewModel.positiveRatedFileCount == 0 {
            return "No rated 2-5 images in the current folder"
        }
        return "Copy \(viewModel.positiveRatedFileCount) rated image\(viewModel.positiveRatedFileCount == 1 ? "" : "s") to a folder"
    }

    private var copyFailureBinding: Binding<Bool> {
        Binding {
            viewModel.copyFailure != nil
        } set: { isPresented in
            if !isPresented {
                viewModel.copyFailure = nil
            }
        }
    }

    private var deleteFailureBinding: Binding<Bool> {
        Binding {
            viewModel.deleteFailure != nil
        } set: { isPresented in
            if !isPresented {
                viewModel.deleteFailure = nil
            }
        }
    }

    private var clipFailureBinding: Binding<Bool> {
        Binding {
            viewModel.clipFeatureError != nil
        } set: { isPresented in
            if !isPresented {
                viewModel.clipFeatureError = nil
            }
        }
    }
}
