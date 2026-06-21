import CoreGraphics
import RawCullCore
import SwiftUI

struct BrowserHistogramView: View {
    let image: CGImage

    @State private var normalizedBins: [CGFloat] = []

    var body: some View {
        ZStack {
            Color.black.opacity(0.24)
                .clipShape(.rect(cornerRadius: 4))

            BrowserHistogramPath(bins: normalizedBins)
                .fill(
                    LinearGradient(
                        colors: [.cyan.opacity(0.9), .purple.opacity(0.85)],
                        startPoint: .top,
                        endPoint: .bottom,
                    ),
                )
                .padding(2)
        }
        .frame(height: 82)
        .task(id: imageIdentifier) {
            normalizedBins = await calculateHistogram(from: image)
        }
        .accessibilityLabel("Histogram")
    }

    private var imageIdentifier: Int {
        ObjectIdentifier(image).hashValue
    }

    private nonisolated func calculateHistogram(from image: CGImage) async -> [CGFloat] {
        await Task.detached(priority: .utility) {
            HistogramCalculator.normalizedLuminanceHistogram(from: image)
        }.value
    }
}
