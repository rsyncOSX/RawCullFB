import SwiftUI

struct FileBrowserView: View {
    @Bindable var viewModel: FileBrowserViewModel
    @State private var columnVisibility = NavigationSplitViewVisibility.doubleColumn

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
        .fileImporter(isPresented: $viewModel.isShowingFolderPicker, allowedContentTypes: [.folder]) { result in
            guard let url = try? result.get() else { return }
            viewModel.addRootFolder(url)
        }
        .fileImporter(isPresented: $viewModel.isShowingCopyDestinationPicker, allowedContentTypes: [.folder]) { result in
            guard let url = try? result.get() else { return }
            Task {
                await viewModel.copySelectedFiles(to: url)
            }
        }
        .alert("Copy Failed", isPresented: copyFailureBinding) {
            Button("OK") {
                viewModel.copyFailure = nil
            }
        } message: {
            Text(viewModel.copyFailure?.message ?? "The selected files could not be copied.")
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                viewModel.isShowingFolderPicker = true
            } label: {
                Label("Add Folder", systemImage: "folder.badge.plus")
            }
            .help("Add a folder to the sidebar")
        }

        ToolbarItemGroup {
            Button {
                viewModel.isShowingCopyDestinationPicker = true
            } label: {
                Label("Copy Selected Files", systemImage: "doc.on.doc")
            }
            .disabled(!viewModel.canCopySelectedFiles)
            .help(copyButtonHelp)

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
            }
        }
    }

    private var copyButtonHelp: String {
        if viewModel.selectedFileCount == 0 {
            return "Select files to copy"
        }
        return "Copy \(viewModel.selectedFileCount) selected file\(viewModel.selectedFileCount == 1 ? "" : "s") to a folder"
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
}
