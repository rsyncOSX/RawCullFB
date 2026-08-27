import CoreGraphics
import RawCullCore

nonisolated enum BrowserHistogramCalculator {
    static let maximumSampleDimension = 512

    /// Calculates a display histogram from a bounded, aspect-preserving sample.
    /// Reading a lazily decoded full-resolution image's data provider would copy
    /// and scan every pixel even though the histogram is only a few hundred
    /// points wide.
    @concurrent static func normalizedLuminanceHistogram(from image: CGImage) async -> [CGFloat] {
        guard !Task.isCancelled else { return [] }
        let sampledImage = sampledImage(from: image)
        guard !Task.isCancelled else { return [] }
        return HistogramCalculator.normalizedLuminanceHistogram(from: sampledImage)
    }

    static func sampledImage(
        from image: CGImage,
        maximumDimension: Int = maximumSampleDimension,
    ) -> CGImage {
        let boundedMaximumDimension = max(maximumDimension, 1)
        let longestDimension = max(image.width, image.height)
        guard longestDimension > boundedMaximumDimension else { return image }

        let scale = CGFloat(boundedMaximumDimension) / CGFloat(longestDimension)
        let sampleWidth = max(Int((CGFloat(image.width) * scale).rounded()), 1)
        let sampleHeight = max(Int((CGFloat(image.height) * scale).rounded()), 1)
        let colorSpace = if image.colorSpace?.model == .rgb {
            image.colorSpace
        } else {
            CGColorSpace(name: CGColorSpace.sRGB)
        }

        guard let colorSpace,
              let context = CGContext(
                  data: nil,
                  width: sampleWidth,
                  height: sampleHeight,
                  bitsPerComponent: 8,
                  bytesPerRow: sampleWidth * 4,
                  space: colorSpace,
                  bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                      | CGImageAlphaInfo.premultipliedLast.rawValue,
              )
        else { return image }

        // Nearest-neighbor sampling preserves source pixel values instead of
        // inventing intermediate luminance values at color boundaries.
        context.interpolationQuality = .none
        context.draw(
            image,
            in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight),
        )
        return context.makeImage() ?? image
    }
}
