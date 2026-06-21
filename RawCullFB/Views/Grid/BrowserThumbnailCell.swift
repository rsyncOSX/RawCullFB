import AppKit
import SwiftUI

struct BrowserThumbnailCell: View {
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
