import AppKit
import SwiftUI

struct BrowserGridView: View {
    @Bindable var viewModel: FileBrowserViewModel
    @FocusState private var isFocused: Bool
    @State private var horizontalThumbnailCount = 1

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

            if viewModel.isSearching {
                ProgressView("Searching…")
                    .padding(14)
                    .background(.regularMaterial, in: .rect(cornerRadius: 8))
            }
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
}
