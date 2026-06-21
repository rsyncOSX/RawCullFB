import Foundation

enum RatedCopyFilter: Hashable, Identifiable {
    case positive
    case rating(Int)
    case rejected

    var id: String {
        switch self {
        case .positive:
            "positive"

        case let .rating(rating):
            "rating-\(rating)"

        case .rejected:
            "rejected"
        }
    }

    var title: String {
        switch self {
        case .positive:
            "Rated 2-5"

        case let .rating(rating):
            "Rated \(rating)"

        case .rejected:
            "Rejected"
        }
    }

    func includes(_ rating: Int) -> Bool {
        switch self {
        case .positive:
            (2 ... 5).contains(rating)

        case let .rating(targetRating):
            rating == targetRating

        case .rejected:
            rating == -1
        }
    }
}
