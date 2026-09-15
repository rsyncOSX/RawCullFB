import CoreAIImageSegmenter
@testable import CoreAISAM3Backend
import CoreGraphics
import Testing

struct SAM3MultiSubjectTests {
    @Test("SAM3 uses its exhaustive semantic map")
    func semanticMapIncludesEverySubject() throws {
        let response = SegmentationResponse(
            segments: [],
            probabilityMap: SemanticSegmentationMap(
                probabilities: [0.9, 0, 0, 0.8],
                width: 4,
                height: 1
            )
        )

        let decoded = try CoreAISAM3Provider.makeMaskImage(from: response, threshold: 0.5)
        let alpha = try #require(alphaPixels(from: decoded.mask))

        #expect(decoded.score == 0.9)
        #expect(alpha[0] == 255)
        #expect(alpha[1] == 0)
        #expect(alpha[2] == 0)
        #expect(alpha[3] == 255)
    }

    @Test("SAM3 unions instance masks when no semantic map is available")
    func instanceFallbackIncludesEverySubject() throws {
        let response = SegmentationResponse(
            segments: [
                segment(mask: [true, false, false, false], score: 0.9),
                segment(mask: [false, false, false, true], score: 0.8),
            ],
            probabilityMap: nil
        )

        let decoded = try CoreAISAM3Provider.makeMaskImage(from: response, threshold: 0.5)
        let alpha = try #require(alphaPixels(from: decoded.mask))

        #expect(alpha[0] == 255)
        #expect(alpha[1] == 0)
        #expect(alpha[2] == 0)
        #expect(alpha[3] == 255)
    }

    private func segment(mask: [Bool], score: Float) -> Segment {
        Segment(
            mask: mask,
            maskWidth: 4,
            maskHeight: 1,
            box: .zero,
            score: score
        )
    }

    private func alphaPixels(from image: CGImage) -> [UInt8]? {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }
    }
}
