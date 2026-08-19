import SwiftUI

struct CLIPIndexesSettingsTab: View {
    @Environment(FileBrowserViewModel.self) private var viewModel

    var body: some View {
        Form {
            CLIPIndexCatalogSection(
                name: viewModel.selectedFolder?.name,
                path: viewModel.selectedFolder?.url.path,
            )

            CLIPIndexStatusSection(
                status: viewModel.clipIndexStatus,
                isIndexing: viewModel.isIndexing,
                progress: viewModel.indexingProgress,
            )

            CLIPIndexReasonSection(
                status: viewModel.clipIndexStatus,
                modelName: viewModel.selectedCLIPModel.displayName,
            )

            Section {
                HStack {
                    Button("Check Again", systemImage: "arrow.clockwise") {
                        viewModel.validateSelectedFolderCLIPIndex()
                    }
                    .disabled(viewModel.selectedFolder == nil || viewModel.isIndexing)

                    if viewModel.isIndexing {
                        Button("Cancel Indexing", role: .cancel) {
                            viewModel.cancelIndexing()
                        }
                    } else {
                        Button(indexButtonTitle, systemImage: "square.stack.3d.up") {
                            viewModel.startIndexingSelectedFolder()
                        }
                        .disabled(!viewModel.canIndexSelectedFolder)
                    }

                    Spacer()
                }
            }
        }
        .formStyle(.grouped)
        .task {
            guard !viewModel.isIndexing else { return }
            viewModel.validateSelectedFolderCLIPIndex()
        }
    }

    private var indexButtonTitle: LocalizedStringKey {
        switch viewModel.clipIndexStatus {
        case .notFound:
            "Create Index"

        case .needsUpdate:
            "Update Index"

        case .invalid:
            "Rebuild Index"

        case .noFolderSelected, .modelRequired, .checking, .valid:
            "Index Catalog"
        }
    }
}

private struct CLIPIndexCatalogSection: View {
    let name: String?
    let path: String?

    var body: some View {
        Section("Selected Catalog") {
            if let name, let path {
                LabeledContent("Name", value: name)
                LabeledContent("Location") {
                    Text(path)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .help(path)
                }
            } else {
                ContentUnavailableView(
                    "No Catalog Selected",
                    systemImage: "folder.badge.questionmark",
                    description: Text("Select a catalog in the main window to inspect its CLIP index."),
                )
            }
        }
    }
}

private struct CLIPIndexStatusSection: View {
    let status: CLIPIndexStatus
    let isIndexing: Bool
    let progress: CLIPIndexingProgress?

    var body: some View {
        Section("Index Status") {
            if isIndexing {
                indexingStatus
            } else {
                currentStatus
            }
        }
    }

    private var indexingStatus: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Indexing catalog…", systemImage: "square.stack.3d.up.fill")
                .foregroundStyle(.blue)

            if let progress {
                ProgressView(value: Double(progress.completed), total: Double(max(progress.total, 1)))
                Text("Indexed \(progress.completed) of \(progress.total)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let currentFileName = progress.currentFileName {
                    Text(currentFileName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var currentStatus: some View {
        switch status {
        case .noFolderSelected:
            statusLabel("No catalog selected", systemImage: "folder", color: .secondary)

        case .modelRequired:
            statusLabel("CLIP model required", systemImage: "exclamationmark.triangle.fill", color: .orange)

        case .checking:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Checking the selected catalog…")
            }
            .foregroundStyle(.secondary)

        case .notFound:
            statusLabel("Not indexed", systemImage: "circle.dashed", color: .secondary)

        case let .valid(_, indexed, updatedAt):
            statusDetails(
                title: "Up to date",
                systemImage: "checkmark.circle.fill",
                color: .green,
                indexed: indexed,
                updatedAt: updatedAt,
            )

        case let .needsUpdate(_, indexed, _, _, _, updatedAt):
            statusDetails(
                title: "Reindex recommended",
                systemImage: "exclamationmark.triangle.fill",
                color: .orange,
                indexed: indexed,
                updatedAt: updatedAt,
            )

        case .invalid:
            statusLabel("Index cannot be used", systemImage: "xmark.octagon.fill", color: .red)
        }
    }

    private func statusLabel(
        _ title: LocalizedStringKey,
        systemImage: String,
        color: Color,
    ) -> some View {
        Label(title, systemImage: systemImage)
            .foregroundStyle(color)
    }

    private func statusDetails(
        title: LocalizedStringKey,
        systemImage: String,
        color: Color,
        indexed: Int,
        updatedAt: Date,
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            statusLabel(title, systemImage: systemImage, color: color)
            LabeledContent("Indexed images") {
                Text(indexed, format: .number)
            }
            LabeledContent("Last updated") {
                Text(updatedAt, format: .dateTime.year().month().day().hour().minute())
            }
        }
    }
}

private struct CLIPIndexReasonSection: View {
    let status: CLIPIndexStatus
    let modelName: String

    var body: some View {
        switch status {
        case .notFound:
            Section("Reason to Index") {
                Text("No index exists for this catalog and the selected \(modelName) model.")
            }

        case let .needsUpdate(_, _, missing, changed, removed, _):
            Section("Reason to Reindex") {
                if missing > 0 {
                    LabeledContent("New images not indexed") {
                        Text(missing, format: .number)
                    }
                }
                if changed > 0 {
                    LabeledContent("Images changed since indexing") {
                        Text(changed, format: .number)
                    }
                }
                if removed > 0 {
                    LabeledContent("Indexed images no longer present") {
                        Text(removed, format: .number)
                    }
                }

                Text("RawCullFB compares image paths, file sizes, modification dates, and index compatibility when checking the catalog.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case let .invalid(_, reason):
            Section("Reason to Reindex") {
                Text(reason)
                    .textSelection(.enabled)
                Text("Rebuilding the index will replace the unusable index with one compatible with the selected model and current index format.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .noFolderSelected, .modelRequired, .checking, .valid:
            EmptyView()
        }
    }
}
