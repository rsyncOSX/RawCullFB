import SwiftUI
import UniformTypeIdentifiers

struct CLIPSettingsTab: View {
    @Environment(FileBrowserViewModel.self) private var viewModel
    @State private var isChoosingModel = false

    var body: some View {
        Form {
            Section("CLIP Model") {
                LabeledContent("Model path") {
                    Text(viewModel.clipModelPath ?? "Not configured")
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }

                HStack {
                    Button("Choose Model…", systemImage: "folder") {
                        isChoosingModel = true
                    }
                    Button("Clear", role: .destructive) {
                        viewModel.clearCLIPModel()
                    }
                    .disabled(viewModel.clipModelPath == nil)
                    Spacer()
                }

                CLIPModelStatusView(status: viewModel.clipModelStatus)
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
        }
        .formStyle(.grouped)
        .fileImporter(
            isPresented: $isChoosingModel,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false,
        ) { result in
            guard case let .success(urls) = result, let url = urls.first else { return }
            viewModel.setCLIPModelURL(url)
        }
    }
}

private struct CLIPModelStatusView: View {
    let status: CLIPModelStatus

    var body: some View {
        LabeledContent("Verification") {
            HStack(spacing: 7) {
                if case .checking = status {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: iconName)
                        .foregroundStyle(statusColor)
                }
                Text(statusText)
                    .foregroundStyle(statusColor)
                    .textSelection(.enabled)
            }
        }
    }

    private var iconName: String {
        switch status {
        case .available: "checkmark.seal.fill"
        case .notConfigured, .missing: "questionmark.circle"
        case .invalid: "xmark.octagon.fill"
        case .checking: "hourglass"
        }
    }

    private var statusColor: Color {
        switch status {
        case .available: .green
        case .invalid: .red
        case .notConfigured, .missing, .checking: .secondary
        }
    }

    private var statusText: String {
        switch status {
        case .notConfigured:
            "Choose a compatible CLIP model bundle."

        case let .checking(url):
            "Verifying \(url.path)"

        case let .available(_, fingerprint, modelName):
            "Valid \(modelName) model (\(fingerprint))"

        case let .missing(url):
            "No model bundle found at \(url.path)"

        case let .invalid(url, reason):
            "Invalid model at \(url.path): \(reason)"
        }
    }
}
