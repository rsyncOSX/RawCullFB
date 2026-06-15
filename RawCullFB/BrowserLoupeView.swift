import SwiftUI

struct BrowserLoupeView: View {
    @Bindable var viewModel: FileBrowserViewModel
    @State private var image: CGImage?
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color.black.opacity(0.94)

                if let image {
                    Image(decorative: image, scale: 1.0, orientation: .up)
                        .resizable()
                        .scaledToFit()
                        .padding(12)
                } else if isLoading {
                    ProgressView()
                        .controlSize(.large)
                } else {
                    ContentUnavailableView("No Selection", systemImage: "photo")
                        .foregroundStyle(.white)
                }
            }

            BrowserFilmstripView(viewModel: viewModel)
        }
        .task(id: viewModel.selectedFileID) {
            await loadSelectedImage()
        }
        .onTapGesture(count: 2) {
            viewModel.openZoom()
        }
    }

    private func loadSelectedImage() async {
        guard let file = viewModel.selectedFile else {
            image = nil
            return
        }
        isLoading = true
        image = await RawImageLoader.shared.extractedJPG(for: file.url)
        isLoading = false
    }
}

private struct BrowserFilmstripView: View {
    @Bindable var viewModel: FileBrowserViewModel

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 8) {
                ForEach(viewModel.files) { file in
                    BrowserFilmstripThumbnail(file: file, isSelected: viewModel.selectedFileID == file.id)
                        .onTapGesture { viewModel.selectFile(file) }
                        .onTapGesture(count: 2) { viewModel.openZoom(for: file) }
                }
            }
            .padding(8)
        }
        .frame(height: 94)
        .background(.bar)
    }
}

private struct BrowserFilmstripThumbnail: View {
    let file: BrowserFileItem
    let isSelected: Bool
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay { ProgressView().controlSize(.small) }
            }
        }
        .frame(width: 76, height: 76)
        .clipShape(.rect(cornerRadius: 5))
        .overlay {
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
        }
        .task(id: file.url) {
            image = await RawImageLoader.shared.thumbnail(for: file.url, targetSize: 200)
        }
    }
}
