import SwiftUI

/// Shares the browser selection, but keeps a deep-review snapshot stable during a run.
struct BrowserAIWorkspaceView: View {
    @Bindable var viewModel: FileBrowserViewModel
    @Environment(\.openWindow) private var openWindow
    @State private var reviewFiles: [BrowserFileItem] = []
    @State private var reviewSignature: BurstGroupSignature?
    @State private var submittedPrompt = ""
    @State private var activeTab = "review"

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Image(systemName: "sparkles").font(.title2).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text("AI Workspace").font(.title2.bold())
                    Text("Select images in the browser, then choose an analysis below.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(viewModel.selectedFileIDs.count) selected").monospacedDigit()
                Button("Show Browser", systemImage: "photo.on.rectangle") {
                    openWindow(id: "main-window")
                }
            }
            .padding(20)
            Divider()
            TabView(selection: $activeTab) {
                Tab("Photo Review", systemImage: "text.bubble", value: "review") {
                    photoReview
                }
                Tab("Subjects & Detail", systemImage: "viewfinder", value: "subjects") {
                    subjectReview
                }
                Tab("Search & Similar", systemImage: "sparkle.magnifyingglass", value: "search") {
                    search
                }
            }
            .padding(16)
        }
        .frame(minWidth: 1120, minHeight: 650)
    }

    private var photoReview: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("Review the selected photos") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Ask about composition, exposure, expression, or visible subjects. Results stay here while you continue browsing.")
                        .foregroundStyle(.secondary)
                    TextField("Review instructions", text: $viewModel.qwenPrompt, axis: .vertical)
                        .lineLimit(2...4)
                        .textFieldStyle(.roundedBorder)
                        .disabled(viewModel.isQwenResponding)
                    HStack {
                        Button("Photo Review") {
                            viewModel.qwenPrompt = FileBrowserViewModel.defaultQwenPrompt
                        }
                        .disabled(viewModel.isQwenResponding)
                        Button("Analyze Objects & Subjects") {
                            viewModel.qwenPrompt = "Identify the main visible objects and subjects. Evaluate their visibility, obstructions, placement, and how clearly they are presented. Describe the main subject and report strengths and problems supported by the image."
                        }
                        .disabled(viewModel.isQwenResponding)
                        .help("Uses the existing vision assessment to describe subjects and object visibility")
                        Spacer()
                        if viewModel.isQwenResponding {
                            if let progress = viewModel.qwenProgress {
                                ProgressView(value: Double(progress.completedCount), total: Double(max(1, progress.totalCount)))
                                    .frame(width: 140)
                                Text("\(progress.completedCount)/\(progress.totalCount)").monospacedDigit()
                            }
                            Button("Cancel", role: .cancel) { viewModel.cancelQwenRequest() }
                        } else {
                            Button("Ask AI", systemImage: "sparkles") {
                                submittedPrompt = viewModel.qwenPrompt
                                viewModel.askQwen()
                            }
                                .buttonStyle(.borderedProminent)
                                .disabled(!viewModel.canAskQwen)
                        }
                    }
                    if !viewModel.qwenModelStatus.isAvailable {
                        Text("Photo review requires a configured Qwen model. Manage models in Settings.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    if let error = viewModel.qwenFeatureError {
                        Text(error).foregroundStyle(.orange).textSelection(.enabled)
                    }
                }
                .padding(8)
            }
            if viewModel.qwenResults.isEmpty {
                ContentUnavailableView("Ready to Review", systemImage: "photo.badge.checkmark",
                    description: Text("Select one or more images and ask AI. Use Command-click or Shift-click to select a group."))
                    .frame(maxHeight: .infinity)
            } else {
                QwenResponseSheetView(prompt: submittedPrompt, results: viewModel.qwenResults,
                    onClose: { viewModel.qwenResults = [] }, isEmbedded: true)
            }
        }
    }

    private var subjectReview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Subject Detail Review").font(.headline)
                    Text("Compare subject sharpness with existing SAM 3 masks, or inspect a single image.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Use Browser Selection") {
                    reviewFiles = viewModel.selectedFiles
                    reviewSignature = BurstGroupSignature(files: reviewFiles, catalog: viewModel.selectedFolder?.url)
                }
                .disabled(!viewModel.canDeepReviewSelection)
            }
            if let signature = reviewSignature {
                DeepAIReviewSheetView(controller: viewModel.deepAIReviewController,
                    groupID: signature.hashValue, groupSignature: signature, files: reviewFiles,
                    onRun: {
                        await viewModel.startDeepReview(groupID: signature.hashValue,
                            groupSignature: signature, files: reviewFiles)
                    }, onApply: { result in
                        if let winner = reviewFiles.first(where: { $0.id == result.recommendedFileID }) {
                            viewModel.selectOnlyFile(winner)
                            openWindow(id: "main-window")
                        }
                    }, onClose: { reviewSignature = nil }, isEmbedded: true)
            } else {
                ContentUnavailableView("Inspect Subjects", systemImage: "viewfinder",
                    description: Text(viewModel.sam3ModelStatus.isAvailable
                        ? "Choose images in the browser, then use the browser selection to prepare a review."
                        : "Subject detail review requires a configured SAM 3 model. Manage models in Settings."))
                    .frame(maxHeight: .infinity)
            }
        }
    }

    private var search: some View {
        Form {
            Section("Find images by description") {
                TextField("For example: a bird flying over water", text: $viewModel.semanticSearchQuery)
                    .onSubmit { viewModel.startSemanticSearch() }
                Button("Search Images", systemImage: "sparkle.magnifyingglass") {
                    viewModel.startSemanticSearch()
                    openWindow(id: "main-window")
                }
                .disabled(!viewModel.canSearch || viewModel.semanticSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Text("Search returns up to \(viewModel.semanticSearchLimit) images using the current Settings.")
                    .foregroundStyle(.secondary)
            }
            Section("Find similar images") {
                Text(viewModel.selectedFile?.name ?? "Select an image in the browser.")
                Button("Find Similar", systemImage: "photo.stack") {
                    viewModel.startSimilaritySearch()
                    openWindow(id: "main-window")
                }
                .disabled(!viewModel.canFindSimilar)
            }
            Section("Folder index") {
                Text(viewModel.selectedFolder?.url.lastPathComponent ?? "Choose a folder in the browser.")
                if viewModel.isIndexing {
                    ProgressView("Indexing images…")
                    Button("Cancel Indexing", role: .cancel) { viewModel.cancelIndexing() }
                } else {
                    Button("Index Selected Folder", systemImage: "square.stack.3d.up") {
                        viewModel.startIndexingSelectedFolder()
                    }
                    .disabled(!viewModel.canIndexSelectedFolder)
                }
                if !viewModel.hasCompatibleCLIPIndex {
                    Text("Search needs a compatible index and a configured CLIP model.")
                        .foregroundStyle(.secondary)
                }
                if viewModel.isSearching { ProgressView("Searching…") }
                if let error = viewModel.clipFeatureError {
                    Text(error).foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
    }
}
