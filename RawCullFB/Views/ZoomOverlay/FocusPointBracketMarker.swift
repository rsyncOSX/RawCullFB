import SwiftUI

struct FocusPointBracketMarker: Shape {
    let normalizedX: CGFloat
    let normalizedY: CGFloat
    let boxSize: CGFloat
    let imageSize: CGSize

    nonisolated func path(in rect: CGRect) -> Path {
        let drawRect = fittedImageRect(imageSize: imageSize, containerSize: rect.size)
        let cx = drawRect.minX + normalizedX * drawRect.width
        let cy = drawRect.minY + normalizedY * drawRect.height
        let half = boxSize / 2
        let bracket = boxSize * 0.28

        var path = Path()
        let corners: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (-1, -1, 1, 0), (-1, -1, 0, 1),
            (1, -1, -1, 0), (1, -1, 0, 1),
            (-1, 1, 1, 0), (-1, 1, 0, -1),
            (1, 1, -1, 0), (1, 1, 0, -1)
        ]

        for (sx, sy, dx, dy) in corners {
            path.move(to: CGPoint(x: cx + sx * half, y: cy + sy * half))
            path.addLine(
                to: CGPoint(
                    x: cx + sx * half + dx * bracket,
                    y: cy + sy * half + dy * bracket,
                ),
            )
        }

        return path
    }
}
