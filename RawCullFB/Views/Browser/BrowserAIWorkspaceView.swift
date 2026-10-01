import SwiftUI

/// Shares the browser selection, but keeps a deep-review snapshot stable during a run.
struct BrowserAIWorkspaceView: View {
    @Bindable var viewModel: FileBrowserViewModel
    @Environment(\.openWindow) private var openWindow
    @State private var reviewFiles: [BrowserFileItem] = []
    @State private var reviewSignature: BurstGroupSignature?
    @State private var submittedPrompt = ""
    @State private var activeTab = "review"
    @State private var reviewType = "assessment"

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
                    unifiedReview
                }
                Tab("Search & Similar", systemImage: "sparkle.magnifyingglass", value: "search") {
                    search
                }
            }
            .padding(16)
        }
        .frame(minWidth: 1120, minHeight: 650)
    }

    private var unifiedReview: some View {
        VStack(spacing: 16) {
            HStack {
                Picker("Review type", selection: $reviewType) {
                    Text("AI Assessment").tag("assessment")
                    Text("Subject Detail").tag("detail")
                }
                .pickerStyle(.segmented)
                .frame(width: 300)
                Spacer()
            }
            if reviewType == "assessment" {
                photoReview
            } else {
                subjectReview
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: reviewType) {
            if reviewType == "detail", reviewSignature == nil, !viewModel.selectedFiles.isEmpty {
                prepareSubjectReview()
            }
        }
    }

    private func prepareSubjectReview() {
        reviewFiles = viewModel.selectedFiles
        reviewSignature = BurstGroupSignature(files: reviewFiles, catalog: viewModel.selectedFolder?.url)
    }

    private var photoReview: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("AI Assessment") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Ask about composition, exposure, expression, or visible subjects. Results stay here while you continue browsing.")
                        .foregroundStyle(.secondary)
                    TextField("Review instructions", text: $viewModel.qwenPrompt, axis: .vertical)
                        .lineLimit(2...4)
                        .textFieldStyle(.roundedBorder)
                        .disabled(viewModel.isQwenResponding)
                    HStack {
                        Menu("Review Presets", systemImage: "text.badge.star") {
                            Button("Composition & Exposure") {
                                viewModel.qwenPrompt = FileBrowserViewModel.defaultQwenPrompt
                            }
                            Button("Objects & Subjects") {
                                viewModel.qwenPrompt = "Identify the main visible objects and subjects. Evaluate their visibility, obstructions, placement, and how clearly they are presented. Describe the main subject and report strengths and problems supported by the image."
                            }
                        }
                        .disabled(viewModel.isQwenResponding)
                        .help("Choose a starting prompt, then adjust the review instructions above.")
                        Spacer()
                        if viewModel.isQwenResponding {
                            if let progress = viewModel.qwenProgress {
                                ProgressView(value: Double(progress.completedCount), total: Double(max(1, progress.totalCount)))
                                    .frame(width: 140)
                                Text("\(progress.completedCount)/\(progress.totalCount)").monospacedDigit()
                            }
                            Button("Cancel", role: .cancel) { viewModel.cancelQwenRequest() }
                        } else {
                            Button("Review Selected Photos", systemImage: "sparkles") {
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
                    description: Text(viewModel.selectedFiles.isEmpty
                        ? "Select photos in the browser, then return here to review composition, exposure, and subjects."
                        : "Adjust the instructions above, then review the selected photos."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    Text("Subject Detail").font(.headline)
                    Text("Compare subject sharpness and inspect subject outlines.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(reviewSignature == nil ? "Review Selected Photos" : "Update from Browser Selection") {
                    prepareSubjectReview()
                }
                .disabled(!viewModel.canDeepReviewSelection || viewModel.deepAIReviewController.isRunning)
            }
            if let signature = reviewSignature {
                Text("Reviewing \(reviewFiles.count) photos from your saved selection.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
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
                ContentUnavailableView("Ready for Subject Review", systemImage: "viewfinder",
                    description: Text(viewModel.sam3ModelStatus.isAvailable
                        ? "Select photos in the browser to compare subject detail and inspect subject outlines."
                        : "Subject detail review requires a configured SAM 3 model. Manage models in Settings."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var search: some View {
        Form {
            Section("Find images by description") {
                TextField("Image description", text: $viewModel.semanticSearchQuery,
                    prompt: Text("For example: a bird flying over water"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
                    .onSubmit { submitSemanticSearch() }
                Button("Search Images", systemImage: "sparkle.magnifyingglass") {
                    submitSemanticSearch()
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
            Section {
                if !viewModel.canSearch && !viewModel.isSearching {
                    Text("Search uses the top-level catalog’s index. Manage the CLIP model and catalog index in Settings.")
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

    private func submitSemanticSearch() {
        guard viewModel.canSearch,
              !viewModel.semanticSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }
        viewModel.startSemanticSearch()
        openWindow(id: "main-window")
    }
}
