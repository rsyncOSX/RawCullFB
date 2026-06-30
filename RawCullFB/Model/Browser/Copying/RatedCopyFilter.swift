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
