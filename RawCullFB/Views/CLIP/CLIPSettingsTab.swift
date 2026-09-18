import SwiftUI

struct CLIPSettingsTab: View {
    @Environment(FileBrowserViewModel.self) private var viewModel
    @State private var showModelDownloads = false
    @State private var showCLIPModelPicker = false
    @State private var showSAM3ModelPicker = false
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

                Text("""
                Downloaded models are used automatically. Selecting a model folder below overrides \
                the downloaded model until the selection is cleared.
                """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("CLIP") {
                CLIPModelStatusRow(status: viewModel.clipModelStatus)

                ViewThatFits {
                    HStack(spacing: 8) { clipActions }
                    VStack(alignment: .leading, spacing: 8) { clipActions }
                }

                Text("""
                Select a local CLIP or SigLIP Core AI bundle for semantic indexing and search, or use \
                the downloadable DataComp CLIP model.
                """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("SAM 3") {
                SAM3ModelStatusRow(status: viewModel.sam3ModelStatus)

                ViewThatFits {
                    HStack(spacing: 8) { sam3Actions }
                    VStack(alignment: .leading, spacing: 8) { sam3Actions }
                }

                Text("Select a local SAM 3 Core AI bundle for Deep Review, or use the downloadable Meta SAM 3 model.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

                Text("""
                Select a local Qwen vision-language Core AI bundle, such as Qwen3-VL-2B-Instruct. \
                RawCullFB validates the bundle but does not download or copy it.
                """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showModelDownloads) {
            CLIPModelDownloadsView(viewModel: viewModel)
        }
        .fileImporter(
            isPresented: $showCLIPModelPicker,
            allowedContentTypes: [.folder],
        ) { result in
            guard let url = try? result.get() else { return }
            viewModel.setCLIPModelURL(url)
        }
        .fileImporter(
            isPresented: $showSAM3ModelPicker,
            allowedContentTypes: [.folder],
        ) { result in
            guard let url = try? result.get() else { return }
            viewModel.setSAM3ModelURL(url)
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
    private var clipActions: some View {
        Button("Select CLIP Model", systemImage: "folder") {
            showCLIPModelPicker = true
        }

        Button("Validate Again", systemImage: "checkmark.shield") {
            viewModel.validateCLIPModelAgain()
        }
        .disabled(viewModel.clipModelStatus == .notConfigured)

        Button("Clear Selection", systemImage: "xmark.circle", role: .destructive) {
            viewModel.clearCLIPModel()
        }
        .disabled(!viewModel.hasSelectedCLIPModelFolder)
    }

    @ViewBuilder
    private var sam3Actions: some View {
        Button("Select SAM 3 Model", systemImage: "folder") {
            showSAM3ModelPicker = true
        }

        Button("Validate Again", systemImage: "checkmark.shield") {
            viewModel.validateSAM3ModelAgain()
        }
        .disabled(!viewModel.canValidateSAM3Model)

        Button("Clear Selection", systemImage: "xmark.circle", role: .destructive) {
            viewModel.clearSAM3Model()
        }
        .disabled(!viewModel.hasSelectedSAM3ModelFolder)
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

private struct CLIPModelStatusRow: View {
    let status: CLIPModelStatus

    var body: some View {
        LabeledContent("CLIP model") {
            switch status {
            case .notConfigured:
                Label("Not installed or selected", systemImage: "minus.circle")
                    .foregroundStyle(.secondary)

            case .checking:
                ProgressView("Validating…")
                    .controlSize(.small)

            case let .available(_, _, modelName):
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

private struct SAM3ModelStatusRow: View {
    let status: RawCullAICapabilityStatus

    var body: some View {
        LabeledContent("SAM 3 model") {
            switch status {
            case .checking:
                ProgressView("Validating…")
                    .controlSize(.small)

            case let .available(location):
                Label(location?.lastPathComponent ?? "Available", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .textSelection(.enabled)

            case let .missing(locations):
                if let location = locations.first {
                    Label("Missing: \(location.lastPathComponent)", systemImage: "questionmark.folder")
                        .foregroundStyle(.orange)
                } else {
                    Label("Not installed or selected", systemImage: "minus.circle")
                        .foregroundStyle(.secondary)
                }

            case let .invalid(_, reason), let .unavailable(reason):
                Label(reason, systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
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
