import SwiftUI

struct BrowserSidebarView: View {
    @Bindable var viewModel: FileBrowserViewModel

    var body: some View {
        List(selection: selectedFolderBinding) {
            Section("Catalogs") {
                ForEach(viewModel.rootFolders) { folder in
                    FolderOutlineRow(viewModel: viewModel, folder: folder, isRootCatalog: true)
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        .overlay {
            if viewModel.rootFolders.isEmpty {
                ContentUnavailableView(
                    "No Folders",
                    systemImage: "folder",
                    description: Text("Add a folder to browse supported raw files."),
                )
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                Button(role: .destructive) {
                    viewModel.isShowingClearCatalogConfirmation = true
                } label: {
                    Label("Clear Remembered Catalogs", systemImage: "trash")
                        .labelStyle(.iconOnly)
                }
                .disabled(viewModel.rootFolders.isEmpty)
                .help("Clear remembered catalogs")
                .buttonStyle(.borderless)
            }
            .padding(10)
            .background(.bar)
        }
        .confirmationDialog(
            "Clear remembered catalogs?",
            isPresented: $viewModel.isShowingClearCatalogConfirmation,
        ) {
            Button("Clear Catalogs", role: .destructive) {
                Task {
                    await viewModel.clearRememberedCatalogs()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes saved catalog entries from the sidebar. It does not delete any files.")
        }
    }

    private var selectedFolderBinding: Binding<BrowserFolderItem.ID?> {
        Binding {
            viewModel.selectedFolder?.id
        } set: { id in
            guard let id, viewModel.isSidebarSelectionEnabled else { return }
            if let folder = viewModel.folder(for: id) {
                viewModel.selectFolder(folder)
            }
        }
    }
}
