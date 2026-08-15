import SwiftUI

struct CLIPSettingsTab: View {
    @Environment(FileBrowserViewModel.self) private var viewModel
    @State private var showModelDownloads = false

    var body: some View {
        @Bindable var viewModel = viewModel

        Form {
            Section("AI Models") {
                ForEach(CLIPManagedModel.allCases) { model in
                    CLIPModelStatusRow(
                        model: model,
                        state: viewModel.clipModelDownloadStates[model.downloadID] ?? .checking,
                    )
                }

                Picker("Selected CLIP model", selection: $viewModel.selectedCLIPModel) {
                    ForEach(CLIPManagedModel.allCases) { model in
                        Text(model.displayName).tag(model)
                    }
                }
                .pickerStyle(.segmented)
                .help("Choose the CLIP model RawCullFB uses for indexing and semantic search.")

                LabeledContent("Active model") {
                    Text(activeModelMessage)
                        .foregroundStyle(viewModel.clipModelStatus.isAvailable ? .green : .secondary)
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
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showModelDownloads) {
            CLIPModelDownloadsView(viewModel: viewModel)
        }
        .task {
            await viewModel.refreshCLIPModels()
        }
    }

    private var activeModelMessage: String {
        let name = viewModel.selectedCLIPModel.displayName
        return switch viewModel.clipModelStatus {
        case let .available(_, _, modelName):
            "\(name) (\(modelName))"

        case .checking:
            "Checking \(name)…"

        case .missing:
            "\(name) is missing"

        case .invalid:
            "\(name) is invalid"

        case .notConfigured:
            "Download \(name) to use it"
        }
    }
}

private struct CLIPModelStatusRow: View {
    let model: CLIPManagedModel
    let state: CLIPModelDownloadState

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: state.iconName)
                .foregroundStyle(state.color)
                .accessibilityHidden(true)

            Text("\(model.displayName) CLIP")

            Spacer()

            Text(state.title)
                .foregroundStyle(state.color)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(model.displayName) CLIP model")
        .accessibilityValue(String(localized: state.title))
    }
}
