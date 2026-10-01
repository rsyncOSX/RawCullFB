import SwiftUI

struct ImageCacheSettingsTab: View {
    @State private var isClearing = false
    @State private var status: String?
    @State private var cacheSize: Int64?
    @State private var sizeError = false
    @State private var thumbnailPath: String?
    @State private var fullSizePath: String?

    var body: some View {
        Form {
            Section("Image Cache") {
                Text("Clear cached thumbnails and full-size JPEG previews, including developed RAW images. Images are cached again when needed. Original photos, AI models, and CLIP indexes are preserved.")
                    .foregroundStyle(.secondary)
                LabeledContent("Cache size") {
                    if let cacheSize {
                        Text(cacheSize, format: .byteCount(style: .file))
                    } else if sizeError {
                        Text("Unavailable")
                    } else {
                        Text("Calculating…")
                    }
                }
                if let thumbnailPath, let fullSizePath {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Thumbnails: \(thumbnailPath)")
                        Text("Full-size previews: \(fullSizePath)")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                }
                Button("Clear Image Cache") {
                    isClearing = true
                    status = nil
                    Task {
                        do {
                            try await RawImageLoader.shared.clearImageCaches()
                            status = "Image cache cleared."
                        } catch {
                            status = "Could not clear the image cache: \(error.localizedDescription)"
                        }
                        await refreshCacheSize()
                        isClearing = false
                    }
                }
                .disabled(isClearing)
                if isClearing { ProgressView("Clearing image cache…") }
                if let status { Text(status) }
            }
        }
        .formStyle(.grouped)
        .task {
            thumbnailPath = await ThumbnailDiskCache.shared.cacheDirectory.path
            fullSizePath = await FullSizeJPGDiskCache.shared.cacheDirectory.path
            await refreshCacheSize()
        }
    }

    private func refreshCacheSize() async {
        do {
            let thumbnails = try await ThumbnailDiskCache.shared.sizeInBytes()
            let fullSize = try await FullSizeJPGDiskCache.shared.sizeInBytes()
            cacheSize = thumbnails + fullSize
            sizeError = false
        } catch {
            cacheSize = nil
            sizeError = true
        }
    }
}
