import SwiftUI

struct FileBrowserView: View {
    @Bindable var viewModel: FileBrowserViewModel
    @State private var columnVisibility = NavigationSplitViewVisibility.doubleColumn
    @State private var folderPickerPurpose: FolderPickerPurpose?
    @State private var isShowingDeleteRejectedConfirmation = false

    var body: some View {
        ZStack {
            NavigationSplitView(columnVisibility: $columnVisibility) {
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
}

private enum FolderPickerPurpose: Equatable {
    case addRootFolder
    case copyRated(RatedCopyFilter)
}
