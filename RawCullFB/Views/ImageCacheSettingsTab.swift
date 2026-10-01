import SwiftUI

struct ImageCacheSettingsTab: View {
    @State private var isClearing = false
    @State private var status: String?

    var body: some View {
        Form {
            Section("Image Cache") {
                Text("Clear cached thumbnails and full-size JPEG previews, including developed RAW images. Images are cached again when needed. Original photos, AI models, and CLIP indexes are preserved.")
                    .foregroundStyle(.secondary)
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
                        isClearing = false
                    }
                }
                .disabled(isClearing)
                if isClearing { ProgressView("Clearing image cache…") }
                if let status { Text(status) }
            }
        }
        .formStyle(.grouped)
    }
}
