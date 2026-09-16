import CoreGraphics
import Foundation

nonisolated enum WholeImageSharpnessScorer {
    static func score(_ image: CGImage) -> Float? {
        let width = min(image.width, 512)
        let height = min(image.height, 512)
        guard width > 2, height > 2 else { return nil }

        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue,
        ) else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var sum: Float = 0
        var squaredSum: Float = 0
        var count: Float = 0
        for y in 1 ..< height - 1 {
            for x in 1 ..< width - 1 {
                let index = y * width + x
                let laplacian = Float(pixels[index]) * 4
                    - Float(pixels[index - 1])
                    - Float(pixels[index + 1])
                    - Float(pixels[index - width])
                    - Float(pixels[index + width])
                sum += laplacian
                squaredSum += laplacian * laplacian
                count += 1
            }
        }
        guard count > 0 else { return nil }
        let mean = sum / count
        let variance = max(0, (squaredSum / count) - (mean * mean))
        return variance / (variance + 1_000)
    }
}
