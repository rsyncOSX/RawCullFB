import SwiftUI

struct BrowserGridView: View {
    @Bindable var viewModel: FileBrowserViewModel

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 14),
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                ForEach(viewModel.files) { file in
                    BrowserThumbnailCell(
                        file: file,
                        isSelected: viewModel.selectedFileID == file.id,
                    )
                    .onTapGesture {
                        viewModel.selectFile(file)
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
        .focusEffectDisabled(true)
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
    }
}

private struct BrowserThumbnailCell: View {
    let file: BrowserFileItem
    let isSelected: Bool

    @State private var image: NSImage?
    @State private var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .controlBackgroundColor))

                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            .aspectRatio(1, contentMode: .fit)
            .clipShape(.rect(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: isSelected ? 3 : 1)
            }

            Text(file.name)
                .font(.caption)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(.rect)
        .task(id: file.url) {
            if let cached = MemoryImageCache.shared.thumbnail(for: file.url) {
                image = cached
                return
            }
            isLoading = true
            image = await RawImageLoader.shared.thumbnail(for: file.url, targetSize: 200)
            isLoading = false
        }
    }
}
