import SwiftUI

struct BrowserSidebarView: View {
    @Bindable var viewModel: FileBrowserViewModel
    @FocusState private var isFocused: Bool

    var body: some View {
        List(selection: selectedFolderBinding) {
            Section("Catalogs") {
                ForEach(viewModel.rootFolders) { folder in
                    FolderOutlineRow(viewModel: viewModel, folder: folder, isRootCatalog: true)
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        .focused($isFocused)
        .simultaneousGesture(
            TapGesture().onEnded {
                if !isFocused {
                    isFocused = true
                }
            },
        )
        .onMoveCommand { direction in
            switch direction {
            case .up:
                viewModel.moveSidebarSelection(by: -1)
            case .down:
                viewModel.moveSidebarSelection(by: 1)
            case .left:
                viewModel.collapseSelectedSidebarFolder()
            case .right:
                viewModel.expandSelectedSidebarFolder()
            @unknown default:
                break
            }
        }
        .overlay {
            if viewModel.rootFolders.isEmpty {
                ContentUnavailableView(
                    "No Folders",
                    systemImage: "folder",
                    description: Text("Please add a folder."),
                )
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            SidebarIndexPanel(viewModel: viewModel)
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

private struct SidebarIndexPanel: View {
    @Bindable var viewModel: FileBrowserViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.isIndexing {
                Button(role: .cancel) {
                    viewModel.cancelIndexing()
                } label: {
                    Label("Cancel Indexing", systemImage: "stop.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            } else {
                Button {
                    viewModel.startIndexingSelectedFolder()
                } label: {
                    Label(indexButtonTitle, systemImage: "square.stack.3d.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canIndexSelectedFolder)
                .help(indexButtonHelp)
            }

            if viewModel.isIndexing {
                indexingProgress
            } else {
                indexStatus
            }
            if viewModel.isShowingSimilarityResults {
                Button {
                    viewModel.clearSemanticSearchResults()
                } label: {
                    Label("Clear Similarity", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .help("Return to the selected folder")
            }

            Button {
                viewModel.startSimilaritySearch()
            } label: {
                Label("Find Similar", systemImage: "photo.stack")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!viewModel.canFindSimilar)
            .help("Rank the indexed folder by similarity to the selected image")
        }
        .padding(10)
        .background(.bar)
    }

    private var indexingProgress: some View {
        VStack(alignment: .leading, spacing: 4) {
            ProgressView(value: completed, total: total)
            Text(indexingProgressText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var indexStatus: some View {
        switch viewModel.clipIndexStatus {
        case .noFolderSelected:
            statusLabel("Select a folder to check its index", systemImage: "folder", color: .secondary)

        case .modelRequired:
            statusLabel("Set and verify a CLIP model in Settings", systemImage: "exclamationmark.triangle", color: .orange)

        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Validating index…")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

        case .notFound:
            statusLabel("No index found", systemImage: "circle.dashed", color: .secondary)

        case let .valid(_, indexed, updatedAt):
            VStack(alignment: .leading, spacing: 2) {
                statusLabel("Valid index · \(indexed) images", systemImage: "checkmark.circle.fill", color: .green)
                updatedLabel(updatedAt)
            }

        case let .needsUpdate(_, indexed, missing, changed, removed, updatedAt):
            VStack(alignment: .leading, spacing: 3) {
                statusLabel("Update recommended", systemImage: "exclamationmark.triangle.fill", color: .orange)
                Text(updateDetails(indexed: indexed, missing: missing, changed: changed, removed: removed))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                updatedLabel(updatedAt)
            }

        case let .invalid(_, reason):
            VStack(alignment: .leading, spacing: 2) {
                statusLabel("Invalid index", systemImage: "xmark.octagon.fill", color: .red)
                Text(reason)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .help(reason)
            }
        }
    }

    private func statusLabel(_ title: String, systemImage: String, color: Color) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func updatedLabel(_ date: Date) -> some View {
        Text("Updated \(date.formatted(date: .abbreviated, time: .shortened))")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

    private var indexButtonTitle: String {
        viewModel.clipIndexStatus.recommendsUpdate ? "Update Index" : "Index Selected Folder"
    }

    private var indexButtonHelp: String {
        if !viewModel.clipModelStatus.isAvailable {
            return "Choose and verify a CLIP model in Settings"
        }
        guard let folder = viewModel.selectedFolder else {
            return "Select a folder to index"
        }
        return "Recursively synchronize the CLIP index in \(folder.url.path)"
    }

    private var completed: Double {
        Double(viewModel.indexingProgress?.completed ?? 0)
    }

    private var total: Double {
        Double(max(viewModel.indexingProgress?.total ?? 1, 1))
    }

    private var indexingProgressText: String {
        guard let progress = viewModel.indexingProgress else { return "Discovering images…" }
        let count = "Indexing \(progress.completed) of \(progress.total)"
        return progress.currentFileName.map { "\(count) · \($0)" } ?? count
    }

    private func updateDetails(indexed: Int, missing: Int, changed: Int, removed: Int) -> String {
        var changes: [String] = []
        if missing > 0 {
            changes.append("\(missing) missing")
        }
        if changed > 0 {
            changes.append("\(changed) changed")
        }
        if removed > 0 {
            changes.append("\(removed) removed")
        }
        return "\(indexed) indexed · \(changes.joined(separator: ", "))."
    }
}
