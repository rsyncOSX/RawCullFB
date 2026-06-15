import SwiftUI

struct FileBrowserView: View {
    @Bindable var viewModel: FileBrowserViewModel
    @State private var columnVisibility = NavigationSplitViewVisibility.doubleColumn

    var body: some View {
        ZStack {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                BrowserSidebarView(viewModel: viewModel)
            } detail: {
                detailContent
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
    }

    @ViewBuilder
    private var detailContent: some View {
        switch viewModel.displayMode {
        case .grid:
            BrowserGridView(viewModel: viewModel)
        case .loupe:
            BrowserLoupeView(viewModel: viewModel)
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

        ToolbarItem(placement: .principal) {
            Picker("View", selection: $viewModel.displayMode) {
                ForEach(BrowserDisplayMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 180)
        }

        ToolbarItemGroup {
            if viewModel.isScanning {
                ProgressView()
                    .controlSize(.small)
                    .help("Discovering supported files")
            } else if viewModel.isCreatingThumbnails {
                ProgressView()
                    .controlSize(.small)
                    .help("Creating 200px memory thumbnails")
            }
        }
    }
}
