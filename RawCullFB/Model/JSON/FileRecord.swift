import Foundation

struct FileRecord: Identifiable, Codable {
    var id = UUID()
    var fileName: String?
    var dateTagged: String?
    var rating: Int?
}
