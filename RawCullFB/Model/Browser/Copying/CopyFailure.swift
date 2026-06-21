import Foundation

struct CopyFailure: Identifiable, Equatable {
    let id = UUID()
    let message: String
}
