import SwiftUI

struct BrowserHistogramPath: Shape {
    let bins: [CGFloat]

    nonisolated func path(in rect: CGRect) -> Path {
        var path = Path()
        guard !bins.isEmpty else { return path }

        let stepX = rect.width / CGFloat(bins.count)
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))

        for (index, value) in bins.enumerated() {
            let x = rect.minX + (CGFloat(index) * stepX)
            let y = rect.maxY - (rect.height * value)
            path.addLine(to: CGPoint(x: x, y: y))
        }

        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
