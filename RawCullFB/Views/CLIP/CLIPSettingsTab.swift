import SwiftUI

struct CLIPSettingsTab: View {
    @Environment(FileBrowserViewModel.self) private var viewModel
    @State private var showModelDownloads = false
    @State private var showQwenModelPicker = false

    var body: some View {
        Form {
            Section("AI Models") {
                ForEach(CLIPModelDownloadCatalog.production.models) { descriptor in
                    AIModelStatusRow(
                        name: descriptor.displayName,
                        state: viewModel.clipModelDownloadStates[descriptor.id] ?? .checking,
                    )
                }

                HStack {
                    Button("Download AI Models", systemImage: "arrow.down.circle") {
                        showModelDownloads = true
                    }

                    Button("Check Again", systemImage: "arrow.clockwise") {
                        Task { await viewModel.refreshCLIPModels() }
                    }

                    Spacer()
                }
            }

            Section("Semantic Search") {
                LabeledContent("Maximum results") {
                    HStack(spacing: 10) {
                        Button("Decrease by 10", systemImage: "minus") {
                            viewModel.adjustSemanticSearchLimit(by: -10)
                        }
                        .labelStyle(.iconOnly)
                        .disabled(viewModel.semanticSearchLimit <= 10)

                        Text(viewModel.semanticSearchLimit, format: .number)
                            .monospacedDigit()
                            .frame(minWidth: 36)

                        Button("Increase by 10", systemImage: "plus") {
                            viewModel.adjustSemanticSearchLimit(by: 10)
                        }
                        .labelStyle(.iconOnly)
                        .disabled(viewModel.semanticSearchLimit >= 500)
                    }
                }

                Text("Search returns up to this many thumbnails. Change the value in steps of ten.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Qwen") {
                QwenModelStatusRow(status: viewModel.qwenModelStatus)

                ViewThatFits {
                    HStack(spacing: 8) { qwenActions }
                    VStack(alignment: .leading, spacing: 8) { qwenActions }
                }

                Text("Select a local Qwen Core AI model bundle. RawCullFB validates the bundle but does not download or copy it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showModelDownloads) {
            CLIPModelDownloadsView(viewModel: viewModel)
        }
        .fileImporter(
            isPresented: $showQwenModelPicker,
            allowedContentTypes: [.folder],
        ) { result in
            guard let url = try? result.get() else { return }
            viewModel.setQwenModelURL(url)
        }
        .task {
            await viewModel.refreshCLIPModels()
        }
    }

    @ViewBuilder
    private var qwenActions: some View {
        Button("Select Qwen Model", systemImage: "folder") {
            showQwenModelPicker = true
        }

        Button("Validate Again", systemImage: "checkmark.shield") {
            viewModel.validateQwenModelAgain()
        }
        .disabled(viewModel.qwenModelStatus == .notConfigured)

        Button("Clear", systemImage: "xmark.circle", role: .destructive) {
            viewModel.clearQwenModel()
        }
        .disabled(viewModel.qwenModelStatus == .notConfigured)
    }
}

private struct QwenModelStatusRow: View {
    let status: QwenModelStatus

    var body: some View {
        LabeledContent("Qwen model") {
            switch status {
            case .notConfigured:
                Label("Not selected", systemImage: "minus.circle")
                    .foregroundStyle(.secondary)

            case .checking:
                ProgressView("Validating…")
                    .controlSize(.small)

            case let .available(_, modelName):
                Label(modelName, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .textSelection(.enabled)

            case let .missing(url):
                Label("Missing: \(url.lastPathComponent)", systemImage: "questionmark.folder")
                    .foregroundStyle(.orange)

            case let .invalid(_, reason):
                Label(reason, systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct AIModelStatusRow: View {
    let name: String
    let state: CLIPModelDownloadState

    var body: some View {
        HStack(spacing: 8) {
            Text(name)

            Spacer()

            if state.isInstalled {
                Label("Installed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Text(state.title)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name) model")
        .accessibilityValue(String(localized: state.title))
    }
}
