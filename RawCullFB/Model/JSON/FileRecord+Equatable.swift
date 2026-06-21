import Foundation

extension FileRecord: Equatable {
    static func == (lhs: FileRecord, rhs: FileRecord) -> Bool {
        lhs.fileName == rhs.fileName &&
            lhs.dateTagged == rhs.dateTagged &&
            lhs.rating == rhs.rating
    }
}
