import SwiftUI

struct ZoomRatingBadgeRow: View {
    let selectedRating: Int?
    let applyRating: (Int) -> Void

    private let badges = [
        RatingBadgeOption(label: "X", rating: -1),
        RatingBadgeOption(label: "P", rating: 0),
        RatingBadgeOption(label: "2", rating: 2),
        RatingBadgeOption(label: "3", rating: 3),
        RatingBadgeOption(label: "4", rating: 4),
        RatingBadgeOption(label: "5", rating: 5)
    ]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(badges) { badge in
                Button {
                    applyRating(badge.rating)
                } label: {
                    BrowserRatingBadge(rating: badge.rating, size: 25)
                        .overlay {
                            if selectedRating == badge.rating {
                                Circle()
                                    .strokeBorder(.white.opacity(0.9), lineWidth: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
                .help("Rate \(badge.label)")
                .accessibilityLabel("Rate \(badge.label)")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
    }
}
