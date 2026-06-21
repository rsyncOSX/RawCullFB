import SwiftUI

struct ZoomImageRatingBadge: View {
    let rating: Int
    let imageSize: CGSize
    let containerSize: CGSize

    var body: some View {
        let drawRect = fittedImageRect(imageSize: imageSize, containerSize: containerSize)
        BrowserRatingBadge(rating: rating, size: 44)
            .position(
                x: drawRect.maxX - 30,
                y: drawRect.maxY - 30,
            )
            .frame(width: containerSize.width, height: containerSize.height)
    }
}
