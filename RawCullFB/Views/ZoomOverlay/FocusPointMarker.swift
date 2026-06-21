import SwiftUI

struct FocusPointMarker: View {
    let focusPoint: BrowserFocusPoint
    let imageSize: CGSize
    let containerSize: CGSize

    var body: some View {
        FocusPointBracketMarker(
            normalizedX: CGFloat(focusPoint.normalizedX),
            normalizedY: CGFloat(focusPoint.normalizedY),
            boxSize: 16,
            imageSize: imageSize,
        )
        .stroke(.red, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        .shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 0)
        .frame(width: containerSize.width, height: containerSize.height)
        .accessibilityLabel("Focus point")
    }
}
