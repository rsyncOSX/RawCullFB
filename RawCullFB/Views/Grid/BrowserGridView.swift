import AppKit
import SwiftUI

struct BrowserGridView: View {
    @Bindable var viewModel: FileBrowserViewModel
    @FocusState private var isFocused: Bool
    @State private var horizontalThumbnailCount = 1
    @State private var deepReviewPresentation: BrowserDeepReviewPresentation?

    private let thumbnailMinimumWidth: CGFloat = 150
    private let thumbnailMaximumWidth: CGFloat = 220
    private let gridSpacing: CGFloat = 3
    private let gridPadding: CGFloat = 16

    private var columns: [GridItem] {
        [
            GridItem(.adaptive(minimum: thumbnailMinimumWidth, maximum: thumbnailMaximumWidth), spacing: gridSpacing)
        ]
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: gridSpacing) {
                    ForEach(viewModel.displayedFiles) { file in
                        BrowserThumbnailCell(
                            file: file,
                            isFocused: viewModel.selectedFileID == file.id,
                            isSelected: viewModel.selectedFileIDs.contains(file.id),
                            thumbnailSize: viewModel.settings.thumbnailSizeGrid,
                            displayPath: viewModel.isShowingSemanticResults ? file.url.path : nil,
                        )
                        .onTapGesture {
                            select(file)
                        }
                        .onTapGesture(count: 2) {
                            viewModel.openZoom(for: file)
                        }
                    }
                }
                .padding(gridPadding)
            }
            .onAppear {
                updateHorizontalThumbnailCount(for: geometry.size.width)
            }
            .onChange(of: geometry.size.width) { _, width in
                updateHorizontalThumbnailCount(for: width)
            }
        }
        .overlay {
            if viewModel.displayedFiles.isEmpty, !viewModel.isScanning, !viewModel.isSearching {
                if viewModel.isShowingSimilarityResults {
                    ContentUnavailableView(
                        "No Similar Images",
                        systemImage: "photo.stack",
                        description: Text("The index contains no other compatible images."),
                    )
                } else {
                    ContentUnavailableView(
                        viewModel.semanticSearchQuery.isEmpty ? "No Supported Files" : "No Semantic Matches",
                        systemImage: viewModel.semanticSearchQuery.isEmpty
                            ? "photo.on.rectangle.angled"
                            : "sparkle.magnifyingglass",
                        description: Text(
                            viewModel.semanticSearchQuery.isEmpty
                                ? "Choose a folder containing RAW, JPEG, TIFF, or PNG files."
                                : "Try a different description or increase the result limit in Settings.",
                        ),
                    )
                }
            }

            if viewModel.isSearching {
                ProgressView("Searching…")
                    .padding(14)
                    .background(.regularMaterial, in: .rect(cornerRadius: 8))
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if viewModel.shouldPresentDeepReviewAction {
                BrowserDeepReviewSelectionBar(
                    selectedCount: viewModel.selectedFileIDs.count,
                    isEnabled: viewModel.canDeepReviewSelection,
                    action: presentDeepReview,
                )
            }
        }
        .sheet(item: $deepReviewPresentation) { presentation in
            DeepAIReviewSheetView(
                controller: viewModel.deepAIReviewController,
                groupID: presentation.groupID,
                groupSignature: presentation.groupSignature,
                files: presentation.files,
                onRun: {
                    await viewModel.startDeepReview(
                        groupID: presentation.groupID,
                        groupSignature: presentation.groupSignature,
                        files: presentation.files,
                    )
                },
                onApply: { result in
                    if let winnerID = result.recommendedFileID,
                       let winner = presentation.files.first(where: { $0.id == winnerID }) {
                        viewModel.selectOnlyFile(winner)
                    }
                    deepReviewPresentation = nil
                },
                onClose: {
                    deepReviewPresentation = nil
                },
            )
        }
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled(true)
        .onAppear {
            isFocused = true
        }
        .onChange(of: viewModel.zoomOverlayVisible) { _, isVisible in
            guard !isVisible else { return }
            Task { @MainActor in
                await Task.yield()
                isFocused = true
            }
        }
        .onKeyPress(.leftArrow) {
            viewModel.navigateSelection(by: -1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            viewModel.navigateSelection(by: 1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            viewModel.navigateSelection(by: -horizontalThumbnailCount)
            return .handled
        }
        .onKeyPress(.downArrow) {
            viewModel.navigateSelection(by: horizontalThumbnailCount)
            return .handled
        }
        .onKeyPress(.return) {
            viewModel.openZoom()
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "nNpP")) { press in
            switch press.characters {
            case "n", "N":
                viewModel.navigateSelection(by: 1)

            case "p", "P":
                viewModel.navigateSelection(by: -1)

            default:
                break
            }
            return .handled
        }
    }

    private func select(_ file: BrowserFileItem) {
        let modifiers = NSEvent.modifierFlags
        if modifiers.contains(.shift) {
            viewModel.extendFileSelection(to: file)
        } else if modifiers.contains(.command) {
            viewModel.toggleFileSelection(file)
        } else {
            viewModel.selectOnlyFile(file)
        }
    }

    private func updateHorizontalThumbnailCount(for width: CGFloat) {
        let availableWidth = max(0, width - (gridPadding * 2))
        let thumbnailCount = Int((availableWidth + gridSpacing) / (thumbnailMinimumWidth + gridSpacing))
        horizontalThumbnailCount = max(1, thumbnailCount)
    }

    private func presentDeepReview() {
        let files = viewModel.selectedFiles
        guard !files.isEmpty, viewModel.canDeepReviewSelection else { return }

        let signature = BurstGroupSignature(
            files: files,
            catalog: viewModel.selectedFolder?.url,
        )
        deepReviewPresentation = BrowserDeepReviewPresentation(
            groupID: signature.hashValue,
            groupSignature: signature,
            files: files,
        )
    }
}

private struct BrowserDeepReviewSelectionBar: View {
    let selectedCount: Int
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("\(selectedCount) selected")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)

            Spacer()

            Button("Deep Review", systemImage: "sparkle.magnifyingglass", action: action)
                .buttonStyle(.bordered)
                .disabled(!isEnabled)
                .help("Review the selected images with local SAM 3 subject-detail analysis")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .accessibilityElement(children: .contain)
    }
}

private struct BrowserDeepReviewPresentation: Identifiable {
    let id = UUID()
    let groupID: Int
    let groupSignature: BurstGroupSignature
    let files: [BrowserFileItem]
}
