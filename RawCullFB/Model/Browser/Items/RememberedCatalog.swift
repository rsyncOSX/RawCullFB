import Foundation

struct RememberedCatalog: Codable, Identifiable {
    var id: String {
        path
    }

    let name: String
    let path: String
    let lastBrowsedAt: Date
    let bookmarkData: Data
}
