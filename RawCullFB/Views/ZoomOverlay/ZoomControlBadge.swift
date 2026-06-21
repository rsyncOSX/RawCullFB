import SwiftUI

struct ZoomControlBadge<Content: View>: View {
    var width: CGFloat = 48
    var height: CGFloat = 28
    let content: Content

    init(
        width: CGFloat = 48,
        height: CGFloat = 28,
        @ViewBuilder content: () -> Content,
    ) {
        self.width = width
        self.height = height
        self.content = content()
    }

    var body: some View {
        content
            .font(.system(size: 17, weight: .semibold))
            .frame(width: width, height: height)
            .background(
                RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                    .fill(ZoomBadgeStyle.fill),
            )
            .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
            .contentShape(RoundedRectangle(cornerRadius: height / 2, style: .continuous))
    }
}
