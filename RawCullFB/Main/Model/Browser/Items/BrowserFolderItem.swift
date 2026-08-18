import Foundation

struct BrowserFolderItem: Identifiable, Hashable {
    let id: URL
    let url: URL
    let name: String
    let supportedFileCount: Int
    let hasCLIPIndex: Bool

    nonisolated init(
        url: URL,
        supportedFileCount: Int = 0,
        hasCLIPIndex: Bool = false,
    ) {
        self.id = url
        self.url = url
        self.name = url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
        self.supportedFileCount = supportedFileCount
        self.hasCLIPIndex = hasCLIPIndex
    }
}
