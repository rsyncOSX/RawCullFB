import Foundation

struct RememberedCatalog: Codable, Identifiable {
    var id: String {
        path
    }

    let path: String
    let bookmarkData: Data
}
