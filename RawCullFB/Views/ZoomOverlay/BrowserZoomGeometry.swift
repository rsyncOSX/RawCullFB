import SwiftUI

enum BrowserZoomViewportMath {
    static func actualPixelsTransform(
        imageSize: CGSize,
        viewportSize: CGSize,
        normalizedFocusPoint: CGPoint?,
    ) -> BrowserZoomViewportTransform {
        let scale = actualPixelsScale(imageSize: imageSize, viewportSize: viewportSize)
        guard let normalizedFocusPoint else {
            return BrowserZoomViewportTransform(scale: scale, offset: .zero)
        }

        let fitRect = fittedImageRect(imageSize: imageSize, containerSize: viewportSize)
        guard fitRect.width > 0, fitRect.height > 0 else {
            return BrowserZoomViewportTransform(scale: scale, offset: .zero)
        }

        let point = CGPoint(
            x: fitRect.minX + normalizedFocusPoint.x * fitRect.width,
            y: fitRect.minY + normalizedFocusPoint.y * fitRect.height,
        )
        let viewportCenter = CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
        let desiredOffset = CGSize(
            width: (viewportCenter.x - point.x) * scale,
            height: (viewportCenter.y - point.y) * scale,
        )
        let scaledImageSize = CGSize(width: fitRect.width * scale, height: fitRect.height * scale)

        return BrowserZoomViewportTransform(
            scale: scale,
            offset: clampedOffset(
                desiredOffset,
                scaledImageSize: scaledImageSize,
                viewportSize: viewportSize,
            ),
        )
    }

    private static func actualPixelsScale(imageSize: CGSize, viewportSize: CGSize) -> CGFloat {
        let fitRect = fittedImageRect(imageSize: imageSize, containerSize: viewportSize)
        guard fitRect.width > 0, fitRect.height > 0 else { return 1.0 }
        let fitScale = min(fitRect.width / imageSize.width, fitRect.height / imageSize.height)
        guard fitScale > 0, fitScale.isFinite else { return 1.0 }
        return 0.6 / fitScale
    }

    private static func clampedOffset(
        _ offset: CGSize,
        scaledImageSize: CGSize,
        viewportSize: CGSize,
    ) -> CGSize {
        let maxX = max(0, (scaledImageSize.width - viewportSize.width) / 2)
        let maxY = max(0, (scaledImageSize.height - viewportSize.height) / 2)
        return CGSize(
            width: min(max(offset.width, -maxX), maxX),
            height: min(max(offset.height, -maxY), maxY),
        )
    }
}

nonisolated func fittedImageRect(imageSize: CGSize, containerSize: CGSize) -> CGRect {
    guard imageSize.width > 0, imageSize.height > 0,
          containerSize.width > 0, containerSize.height > 0
    else { return .zero }

    let scale = min(containerSize.width / imageSize.width, containerSize.height / imageSize.height)
    let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    return CGRect(
        x: (containerSize.width - size.width) / 2,
        y: (containerSize.height - size.height) / 2,
        width: size.width,
        height: size.height,
    )
}
