import Foundation

struct RatingBadgeOption: Identifiable {
    var id: Int {
        rating
    }

    let label: String
    let rating: Int
}
