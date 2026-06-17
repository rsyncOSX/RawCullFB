import AppKit
import SwiftUI

struct BrowserGridView: View {
    @Bindable var viewModel: FileBrowserViewModel
    @FocusState private var isFocused: Bool

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 3)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 3) {
                ForEach(viewModel.files) { file in
                    BrowserThumbnailCell(
                        file: file,
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
            .padding(16)
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
}

private struct BrowserThumbnailCell: View {
    let file: BrowserFileItem
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
