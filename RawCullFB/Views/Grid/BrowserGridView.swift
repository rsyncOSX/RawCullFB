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
                    ForEach(viewModel.files) { file in
                        BrowserThumbnailCell(
                            file: file,
                            rating: viewModel.settings.enableRatingPins ? viewModel.rating(for: file) : nil,
                            isFocused: viewModel.selectedFileID == file.id,
                            isSelected: viewModel.selectedFileIDs.contains(file.id),
                            thumbnailSize: viewModel.settings.thumbnailSizeGrid,
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
            if viewModel.files.isEmpty, !viewModel.isScanning {
                ContentUnavailableView(
                    "No Supported Files",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text("Choose a folder containing RAW, JPEG, TIFF, or PNG files."),
                )
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
        .onKeyPress(characters: CharacterSet(charactersIn: "nNzZxXpP012345tT")) { press in
            if viewModel.settings.enableRatingPins,
               let rating = BrowserRatingShortcut.rating(for: press.characters) {
                return viewModel.updateSelectedFilesRatingAndAdvance(rating) ? .handled : .ignored
            }

            switch press.characters {
            case "n", "N":
                viewModel.navigateSelection(by: 1)

            case "p", "P":
                viewModel.navigateSelection(by: -1)

            case "z", "Z":
                viewModel.openZoom(initialZoomMode: .actualPixels, showFocusPointOnOpen: true)

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
