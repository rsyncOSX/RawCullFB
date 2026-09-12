import SwiftUI

struct CLIPSettingsTab: View {
    @Environment(FileBrowserViewModel.self) private var viewModel
    @State private var showModelDownloads = false

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
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showModelDownloads) {
            CLIPModelDownloadsView(viewModel: viewModel)
        }
        .task {
            await viewModel.refreshCLIPModels()
        }
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
