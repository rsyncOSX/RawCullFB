import Foundation

struct BrowserFileItem: Identifiable, Hashable {
    let id: UUID
    let url: URL
    let name: String
    let byteCount: Int64
    let modifiedDate: Date?

    nonisolated init(url: URL, byteCount: Int64 = 0, modifiedDate: Date? = nil) {
        self.id = UUID()
        self.url = url
        self.name = url.lastPathComponent
        self.byteCount = byteCount
        self.modifiedDate = modifiedDate
    }
}
