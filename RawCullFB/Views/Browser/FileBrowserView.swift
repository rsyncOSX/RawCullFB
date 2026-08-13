import SwiftUI

struct FileBrowserView: View {
    @Bindable var viewModel: FileBrowserViewModel

    var body: some View {
        ZStack {
            NavigationSplitView {
                BrowserSidebarView(viewModel: viewModel)
            } detail: {
                BrowserGridView(viewModel: viewModel)
                    .navigationTitle(viewModel.title)
                    .toolbar { toolbarContent }
            }

            if viewModel.zoomOverlayVisible {
                BrowserZoomOverlayView(viewModel: viewModel)
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .fileImporter(isPresented: $viewModel.isShowingFolderPicker, allowedContentTypes: [.folder]) { result in
            guard let url = try? result.get() else { return }
            viewModel.addRootFolder(url)
        }
        .alert("CLIP Operation Failed", isPresented: clipFailureBinding) {
            Button("OK") {
                viewModel.clipFeatureError = nil
            }
        } message: {
            Text(viewModel.clipFeatureError ?? "The CLIP operation could not be completed.")
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                viewModel.isShowingFolderPicker = true
            } label: {
                Label("Add Folder", systemImage: "folder.badge.plus")
            }
            .help("Add a folder to the sidebar")
        }

        ToolbarItemGroup {
            TextField("Semantic search", text: $viewModel.semanticSearchQuery)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 180, idealWidth: 260, maxWidth: 340)
                .disabled(
                    !viewModel.hasCompatibleCLIPIndex
                        || viewModel.isIndexing
                        || viewModel.isRunningSemanticTest,
                )
                .onSubmit {
                    viewModel.startSemanticSearch()
                }

            Button {
                viewModel.startSemanticSearch()
            } label: {
                Label("Search", systemImage: "sparkle.magnifyingglass")
            }
            .disabled(!viewModel.canSearch || viewModel.semanticSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help("Search the CLIP index and show up to \(viewModel.semanticSearchLimit) results")

            Button {
                viewModel.adjustSemanticSearchLimit(by: -10)
            } label: {
                Label("Decrease Results by 10", systemImage: "minus")
            }
            .labelStyle(.iconOnly)
            .disabled(
                viewModel.semanticSearchLimit <= 10
                    || viewModel.isRunningSemanticTest,
            )
            .help("Decrease the semantic result limit by 10")

            Text(viewModel.semanticSearchLimit, format: .number)
                .monospacedDigit()
                .frame(minWidth: 28)
                .help("Maximum semantic search results")

            Button {
                viewModel.adjustSemanticSearchLimit(by: 10)
            } label: {
                Label("Increase Results by 10", systemImage: "plus")
            }
            .labelStyle(.iconOnly)
            .disabled(
                viewModel.semanticSearchLimit >= 500
                    || viewModel.isRunningSemanticTest,
            )
            .help("Increase the semantic result limit by 10")

            if viewModel.isShowingSemanticResults, !viewModel.isRunningSemanticTest {
                Button {
                    viewModel.clearSemanticSearchResults()
                } label: {
                    Label("Clear Search", systemImage: "xmark.circle")
                }
                .help("Clear semantic search results")
            }

            if viewModel.addSemanticTest {
                if viewModel.isRunningSemanticTest {
                    Button(role: .cancel) {
                        viewModel.cancelSemanticTest()
                    } label: {
                        Label("Cancel Model Test", systemImage: "stop.circle")
                    }
                    .help("Stop after preserving all completed model test results")

                    if let progress = viewModel.semanticTestProgress {
                        Text(
                            "\(progress.completedQueryCount)/\(progress.totalQueryCount)",
                            comment: "Completed semantic test queries followed by total queries.",
                        )
                        .font(.caption.monospacedDigit())
                        .help(progress.currentQuery ?? "Comparing indexed images")
                        .accessibilityLabel("Model test progress")
                        .accessibilityValue(
                            "\(progress.completedQueryCount) of \(progress.totalQueryCount) queries completed",
                        )
                    }
                } else {
                    Button {
                        viewModel.startSemanticTest()
                    } label: {
                        Label("Run Model Test", systemImage: "checklist")
                    }
                    .disabled(!viewModel.canRunSemanticTest)
                    .help("Run semantic queries, compare every indexed image, and save model-prefixed results")

                    if let outcome = viewModel.semanticTestOutcome {
                        Text("Test \(outcome.completedQueryCount)/\(outcome.totalQueryCount)")
                            .font(.caption.monospacedDigit())
                            .help("Results saved to \(outcome.resultFileURL.lastPathComponent)")
                            .accessibilityLabel("Last model test result")
                            .accessibilityValue(
                                "\(outcome.completedQueryCount) of \(outcome.totalQueryCount) queries saved",
                            )
                    }
                }
            }

            if viewModel.isScanning {
                ProgressView()
                    .controlSize(.small)
                    .help("Discovering supported files")
            } else if viewModel.isCreatingThumbnails {
                ProgressView()
                    .controlSize(.small)
                    .help("Creating 200px memory thumbnails")
            } else if viewModel.isSearching || viewModel.isRunningSemanticTest {
                ProgressView()
                    .controlSize(.small)
                    .help(
                        viewModel.isRunningSemanticTest
                            ? "Running semantic test queries"
                            : "Searching the CLIP index",
                    )
            }
        }
    }

    private var clipFailureBinding: Binding<Bool> {
        Binding {
            viewModel.clipFeatureError != nil
        } set: { isPresented in
            if !isPresented {
                viewModel.clipFeatureError = nil
            }
        }
    }
}
