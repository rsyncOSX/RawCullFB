import SwiftUI

struct BrowserSidebarView: View {
    @Bindable var viewModel: FileBrowserViewModel

    var body: some View {
        List(selection: selectedFolderBinding) {
            Section("Catalogs") {
                ForEach(viewModel.rootFolders) { folder in
                    folderRow(folder)
                }
            }

            if !viewModel.childFolders.isEmpty {
                Section("Folders") {
                    ForEach(viewModel.childFolders) { folder in
                        folderRow(folder)
                    }
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
    }

    private var selectedFolderBinding: Binding<BrowserFolderItem.ID?> {
        Binding {
            viewModel.selectedFolder?.id
        } set: { id in
            guard let id else { return }
            if let folder = (viewModel.rootFolders + viewModel.childFolders).first(where: { $0.id == id }) {
                viewModel.selectFolder(folder)
            }
        }
    }

    private func folderRow(_ folder: BrowserFolderItem) -> some View {
        Label {
            HStack {
                Text(folder.name)
                    .lineLimit(1)
                Spacer()
                if folder.supportedFileCount > 0 {
                    Text("\(folder.supportedFileCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        } icon: {
            Image(systemName: folder.supportedFileCount > 0 ? "folder.fill" : "folder")
                .foregroundStyle(folder.supportedFileCount > 0 ? .blue : .secondary)
        }
        .tag(folder.id)
    }
}
