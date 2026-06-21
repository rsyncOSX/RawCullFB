import Foundation

struct CopyProgress: Equatable {
    var completedCount = 0
    var totalCount = 0

    var isActive: Bool {
        totalCount > 0 && completedCount < totalCount
    }
}
