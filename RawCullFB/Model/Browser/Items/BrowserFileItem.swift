import Foundation

struct BrowserFileItem: Identifiable, Hashable {
    let id: UUID
    let url: URL
    let name: String

    nonisolated init(url: URL) {
        self.id = UUID()
        self.url = url
        self.name = url.lastPathComponent
    }
}
