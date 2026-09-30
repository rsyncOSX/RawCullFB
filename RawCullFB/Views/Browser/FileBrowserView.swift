import SwiftUI

struct FileBrowserView: View {
    @Bindable var viewModel: FileBrowserViewModel
    @Environment(\.openWindow) private var openWindow

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
        .fileImporter(isPresented: $viewModel.isShowingFolderPicker, allowedContentTypes: [.folder]) { result in
            guard let url = try? result.get() else { return }
            viewModel.addRootFolder(url)
        }
        .alert("CLIP Operation Failed", isPresented: clipFailureBinding) {
            Button("OK") {
                viewModel.clipFeatureError = nil
            }
        } message: {
            Text(viewModel.clipFeatureError ?? "The CLIP operation could not be completed.")
        }
        .alert("Qwen Request Failed", isPresented: qwenFailureBinding) {
            Button("OK") {
                viewModel.qwenFeatureError = nil
            }
        } message: {
            Text(viewModel.qwenFeatureError ?? "The Qwen request could not be completed.")
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
            Button("Preview", systemImage: "arrow.up.left.and.arrow.down.right") {
                viewModel.openZoom()
            }
            .disabled(viewModel.selectedFile == nil)
            .help("Preview the selected image (Return)")

            Button("AI Workspace", systemImage: "sparkles.rectangle.stack") {
                openWindow(id: "ai-workspace")
            }
            .help("Review, analyze subjects, and search while browsing")

            if viewModel.isScanning || viewModel.isCreatingThumbnails {
                ProgressView().controlSize(.small)
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

    private var qwenFailureBinding: Binding<Bool> {
        Binding {
            viewModel.qwenFeatureError != nil
        } set: { isPresented in
            if !isPresented {
                viewModel.qwenFeatureError = nil
            }
        }
    }

}
