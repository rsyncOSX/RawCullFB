import AppKit
import SwiftUI

struct CLIPModelDownloadsView: View {
    @Bindable var viewModel: FileBrowserViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("AI Model Downloads")
                    .font(.title2.weight(.semibold))

                Text("RawCullFB uses on-demand Managed Background Assets. macOS stores and manages downloaded models, which run locally after installation. Their current access location can change between app launches.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(CLIPModelDownloadCatalog.production.models) { descriptor in
                        CLIPModelDownloadRow(
                            descriptor: descriptor,
                            state: viewModel.clipModelDownloadStates[descriptor.id] ?? .checking,
                            viewModel: viewModel,
                        )
                    }
                }
                .padding(.vertical, 2)
            }

            HStack {
                Text("Models run locally after installation. RawCullFB never uploads photographs as part of a model download.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 660, height: 600)
        .task {
            await viewModel.refreshCLIPModels()
        }
    }
}

private struct CLIPModelDownloadRow: View {
    let descriptor: CLIPModelDownloadDescriptor
    let state: CLIPModelDownloadState
    let viewModel: FileBrowserViewModel
    @State private var showRemoveConfirmation = false

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(descriptor.displayName)
                        .font(.headline)

                    Spacer()

                    Label(state.title, systemImage: state.iconName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(state.color)
                }

                Text(descriptor.purpose)
                    .font(.callout)

                Text("Publisher: \(descriptor.publisher) · Version: \(descriptor.modelVersion)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Text("Download size: \(ByteCountFormatter.string(fromByteCount: descriptor.downloadByteCount, countStyle: .file))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if case .installed = state {
                    Text("Stored and managed by macOS.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if case let .failed(message) = state {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Licence: \(descriptor.licenceName)")
                        .font(.caption.weight(.medium))
                    Text(descriptor.licenceSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                progressView

                ViewThatFits {
                    HStack(spacing: 8) { actionButtons }
                    VStack(alignment: .leading, spacing: 8) { actionButtons }
                }
            }
            .padding(4)
        }
        .confirmationDialog(
            "Remove downloaded model?",
            isPresented: $showRemoveConfirmation,
        ) {
            Button("Remove Model", role: .destructive) {
                Task { await viewModel.removeManagedCLIPModel(descriptor.id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("RawCullFB will remove only its managed asset pack.")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(descriptor.displayName)
    }

    @ViewBuilder
    private var progressView: some View {
        switch state {
        case let .downloading(progress):
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: progress)
                Text(progress, format: .percent.precision(.fractionLength(0)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Model download progress")

        case .checking, .validating, .removing:
            ProgressView(state.activityTitle)
                .controlSize(.small)

        case .notConfigured, .ready, .installed, .failed:
            EmptyView()
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        Link("Licence", destination: descriptor.licenceURL)
        Link("Model Card", destination: descriptor.modelCardURL)

        switch state {
        case .ready:
            Button("Download", systemImage: "arrow.down.circle") {
                viewModel.startCLIPModelDownload(descriptor.id)
            }
            .accessibilityHint("Downloads this model locally using Managed Background Assets.")

        case .downloading:
            Button("Cancel Download", systemImage: "xmark.circle", role: .cancel) {
                viewModel.cancelCLIPModelDownload(descriptor.id)
            }

        case let .installed(location):
            Button("Show in Finder", systemImage: "folder") {
                NSWorkspace.shared.activateFileViewerSelecting([location])
            }

            Button("Remove", systemImage: "trash", role: .destructive) {
                showRemoveConfirmation = true
            }

        case .failed:
            Button("Retry", systemImage: "arrow.clockwise") {
                viewModel.startCLIPModelDownload(descriptor.id)
            }

        case .checking, .notConfigured, .validating, .removing:
            EmptyView()
        }
    }
}

extension CLIPModelDownloadState {
    var title: LocalizedStringResource {
        switch self {
        case .checking: "Checking"
        case .notConfigured: "Server pending"
        case .ready: "Ready"
        case .downloading: "Downloading"
        case .validating: "Validating"
        case .installed: "Installed"
        case .removing: "Removing"
        case .failed: "Failed"
        }
    }

    var activityTitle: LocalizedStringResource {
        switch self {
        case .checking: "Checking model service…"
        case .validating: "Validating model…"
        case .removing: "Removing model…"
        case .notConfigured, .ready, .downloading, .installed, .failed: ""
        }
    }

    var iconName: String {
        switch self {
        case .checking: "arrow.triangle.2.circlepath"
        case .notConfigured: "network.slash"
        case .ready: "arrow.down.circle"
        case .downloading: "arrow.down.circle.fill"
        case .validating: "checkmark.shield"
        case .installed: "checkmark.circle.fill"
        case .removing: "trash.circle"
        case .failed: "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .installed: .green
        case .ready, .downloading, .validating: .blue
        case .checking, .removing: .secondary
        case .notConfigured: .orange
        case .failed: .red
        }
    }
}
