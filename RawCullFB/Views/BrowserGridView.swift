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
                    description: Text("Choose a folder containing supported raw files."),
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
        .onKeyPress(characters: CharacterSet(charactersIn: "nNxXpP012345tT")) { press in
            if viewModel.settings.enableRatingPins,
               let rating = BrowserRatingShortcut.rating(for: press.characters) {
                return viewModel.updateSelectedFilesRatingAndAdvance(rating) ? .handled : .ignored
            }

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

private struct BrowserThumbnailCell: View {
    let file: BrowserFileItem
    let rating: Int?
    let isFocused: Bool
    let isSelected: Bool

    @State private var image: NSImage?
    @State private var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            thumbnail

            Text(file.name)
                .font(.caption)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(.rect)
        .task(id: file.url) {
            if let cached = await MemoryImageCache.shared.thumbnail(for: file.url) {
                image = cached
                return
            }
            isLoading = true
            image = await RawImageLoader.shared.thumbnail(for: file.url, targetSize: 200)
            isLoading = false
        }
        .onDisappear {
            image = nil
            isLoading = false
        }
    }

    private var thumbnail: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color(nsColor: .controlBackgroundColor))
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                GeometryReader { geometry in
                    thumbnailContent
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
            .clipShape(.rect(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(borderColor, lineWidth: isSelected ? 3 : 1)
            }
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: isFocused ? "checkmark.circle.fill" : "checkmark.circle")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.accentColor)
                        .padding(6)
                }
            }
            .overlay(alignment: .topLeading) {
                if let rating {
                    BrowserRatingBadge(rating: rating, size: 30)
                        .padding(6)
                }
            }
    }

    private var borderColor: Color {
        if isFocused {
            return .accentColor
        }
        if isSelected {
            return .accentColor.opacity(0.72)
        }
        return .primary.opacity(0.08)
    }

    @ViewBuilder
    private var thumbnailContent: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .clipped()
        } else if isLoading {
            ProgressView()
                .controlSize(.small)
        } else {
            Image(systemName: "photo")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
        }
    }
}
