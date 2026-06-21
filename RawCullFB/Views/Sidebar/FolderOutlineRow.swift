import SwiftUI

struct FolderOutlineRow: View {
    @Bindable var viewModel: FileBrowserViewModel
    let folder: BrowserFolderItem
    let isRootCatalog: Bool

    var body: some View {
        if shouldShowDisclosure {
            DisclosureGroup(isExpanded: expandedBinding) {
                ForEach(viewModel.children(of: folder)) { child in
                    FolderOutlineRow(viewModel: viewModel, folder: child, isRootCatalog: false)
                }
            } label: {
                folderLabel
            }
            .tag(folder.id)
            .selectionDisabled(!viewModel.isSidebarSelectionEnabled)
            .contextMenu {
                rootCatalogDeleteButton
            }
        } else {
            folderLabel
                .tag(folder.id)
                .selectionDisabled(!viewModel.isSidebarSelectionEnabled)
                .contextMenu {
                    rootCatalogDeleteButton
                }
        }
    }

    private var shouldShowDisclosure: Bool {
        !viewModel.hasLoadedChildren(for: folder) || !viewModel.children(of: folder).isEmpty
    }

    private var expandedBinding: Binding<Bool> {
        Binding {
            viewModel.isFolderExpanded(folder)
        } set: { isExpanded in
            viewModel.setFolder(folder, expanded: isExpanded)
        }
    }

    private var folderLabel: some View {
        Label {
            HStack {
                Text(displayName)
                    .lineLimit(1)
                Spacer()
                if let imageCountText {
                    Text(imageCountText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        } icon: {
            Image(systemName: folder.supportedFileCount > 0 ? "folder.fill" : "folder")
                .foregroundStyle(folder.supportedFileCount > 0 ? .blue : .secondary)
        }
    }

    private var displayName: String {
        guard isRootCatalog, !viewModel.children(of: folder).isEmpty else { return folder.name }
        return folder.name
    }

    private var imageCountText: String? {
        guard folder.supportedFileCount > 0 else { return nil }
        let ratedFileCount = viewModel.ratedFileCount(in: folder)
        if ratedFileCount > 0 {
            return "\(folder.supportedFileCount) (\(ratedFileCount))"
        }
        return "\(folder.supportedFileCount)"
    }

    @ViewBuilder
    private var rootCatalogDeleteButton: some View {
        if isRootCatalog {
            Button("Delete Catalog from Sidebar", role: .destructive) {
                Task {
                    await viewModel.removeRootCatalog(folder)
                }
            }
        }
    }
}
