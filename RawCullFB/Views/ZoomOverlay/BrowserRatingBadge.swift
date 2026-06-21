import SwiftUI

struct BrowserRatingBadge: View {
    let rating: Int
    var size: CGFloat = 32

    var body: some View {
        Text(Self.label(for: rating))
            .font(.system(size: size * 0.46, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Self.textColor(for: rating))
            .frame(width: size, height: size)
            .background(
                Circle()
                    .fill(ZoomBadgeStyle.fill),
            )
            .shadow(color: .black.opacity(0.55), radius: 3, x: 0, y: 1)
            .accessibilityLabel("Rating \(Self.label(for: rating))")
    }

    private static func label(for rating: Int) -> String {
        switch rating {
        case -1:
            "X"

        case 0:
            "P"

        default:
            "\(rating)"
        }
    }

    private static func textColor(for rating: Int) -> Color {
        switch rating {
        case -1:
            .red

        case 0:
            .blue

        case 2:
            .yellow

        case 3:
            .green

        case 4:
            .cyan

        case 5:
            .pink

        default:
            .primary
        }
    }
}
