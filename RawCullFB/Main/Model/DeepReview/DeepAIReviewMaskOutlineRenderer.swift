import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins

nonisolated enum DeepAIReviewMaskOutlineRenderer {
    @concurrent
    static func outline(from mask: CGImage) async -> CGImage? {
        guard mask.width > 0, mask.height > 0, !Task.isCancelled else { return nil }

        let input = CIImage(cgImage: mask)
        let extent = input.extent

        let extractAlpha = CIFilter.colorMatrix()
        extractAlpha.inputImage = input
        let alphaVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        extractAlpha.rVector = alphaVector
        extractAlpha.gVector = alphaVector
        extractAlpha.bVector = alphaVector
        extractAlpha.aVector = alphaVector
        guard let alpha = extractAlpha.outputImage?.cropped(to: extent) else { return nil }

        let threshold = CIFilter.colorThreshold()
        threshold.inputImage = alpha
        threshold.threshold = 0.5
        guard let binary = threshold.outputImage?.cropped(to: extent) else { return nil }

        let minimumDimension = Float(min(mask.width, mask.height))
        let radius = min(max(minimumDimension / 300, 2), 14)

        let dilate = CIFilter.morphologyMaximum()
        dilate.inputImage = binary
        dilate.radius = radius

        let erode = CIFilter.morphologyMinimum()
        erode.inputImage = binary
        erode.radius = radius

        guard let outer = dilate.outputImage?.cropped(to: extent),
              let inner = erode.outputImage?.cropped(to: extent)
        else { return nil }

        let difference = CIFilter.differenceBlendMode()
        difference.inputImage = outer
        difference.backgroundImage = inner
        guard let contour = difference.outputImage?.cropped(to: extent) else { return nil }

        let contourAlpha = CIFilter.colorMatrix()
        contourAlpha.inputImage = contour
        let redVector = CIVector(x: 1, y: 0, z: 0, w: 0)
        contourAlpha.rVector = redVector
        contourAlpha.gVector = redVector
        contourAlpha.bVector = redVector
        contourAlpha.aVector = redVector
        guard let output = contourAlpha.outputImage?.cropped(to: extent),
              !Task.isCancelled
        else { return nil }

        let context = CIContext(options: [.cacheIntermediates: false, .workingColorSpace: NSNull()])
        return context.createCGImage(output, from: extent)
    }
}
