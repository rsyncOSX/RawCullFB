import CoreGraphics
@testable import RawCullFB
import Testing

@Suite("Browser histogram calculator")
struct BrowserHistogramCalculatorTests {
    @Test
    func `Bounds the sampled image while preserving its aspect ratio`() throws {
        let image = try makeSplitImage(width: 1_024, height: 512)

        let sampledImage = BrowserHistogramCalculator.sampledImage(from: image)

        #expect(sampledImage.width == BrowserHistogramCalculator.maximumSampleDimension)
        #expect(sampledImage.height == BrowserHistogramCalculator.maximumSampleDimension / 2)
    }

    @Test
    func `Sampled histogram preserves dominant luminance values`() async throws {
        let image = try makeSplitImage(width: 1_024, height: 512)

        let histogram = await BrowserHistogramCalculator.normalizedLuminanceHistogram(from: image)

        #expect(histogram.count == 256)
        #expect(histogram[0] == 1)
        #expect(histogram[255] == 1)
        #expect(histogram[1 ..< 255].allSatisfy { $0 == 0 })
    }

    private func makeSplitImage(width: Int, height: Int) throws -> CGImage {
        let context = try #require(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                | CGImageAlphaInfo.premultipliedLast.rawValue,
        ))
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: width / 2, y: 0, width: width / 2, height: height))
        return try #require(context.makeImage())
    }
}
