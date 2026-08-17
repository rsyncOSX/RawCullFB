import Foundation
@testable import RawCullFB
import Testing

@Suite("Sidebar keyboard navigation")
struct SidebarKeyboardNavigationTests {
    @Test
    func `Visible folders follow expanded catalog hierarchy`() {
        let viewModel = FileBrowserViewModel()
        let catalog = folder("catalog")
        let first = folder("catalog/first")
        let nested = folder("catalog/first/nested")
        let second = folder("catalog/second")

        viewModel.rootFolders = [catalog]
        viewModel.folderChildren[catalog.id] = [first, second]
        viewModel.folderChildren[first.id] = [nested]

        #expect(viewModel.visibleSidebarFolders.map(\.id) == [catalog.id])

        viewModel.expandedFolderIDs = [catalog.id]
        #expect(viewModel.visibleSidebarFolders.map(\.id) == [catalog.id, first.id, second.id])

        viewModel.expandedFolderIDs.insert(first.id)
        #expect(viewModel.visibleSidebarFolders.map(\.id) == [catalog.id, first.id, nested.id, second.id])
    }

    @Test
    func `Horizontal arrows expand and collapse the selected folder`() {
        let viewModel = FileBrowserViewModel()
        let catalog = folder("catalog")
        let child = folder("catalog/child")

        viewModel.rootFolders = [catalog]
        viewModel.folderChildren[catalog.id] = [child]
        viewModel.selectedFolder = catalog

        #expect(viewModel.expandSelectedSidebarFolder())
        #expect(viewModel.isFolderExpanded(catalog))
        #expect(!viewModel.expandSelectedSidebarFolder())

        #expect(viewModel.collapseSelectedSidebarFolder())
        #expect(!viewModel.isFolderExpanded(catalog))
        #expect(!viewModel.collapseSelectedSidebarFolder())
    }

    @Test
    func `Leaf folders do not expand`() {
        let viewModel = FileBrowserViewModel()
        let leaf = folder("catalog/leaf")

        viewModel.rootFolders = [leaf]
        viewModel.folderChildren[leaf.id] = []
        viewModel.selectedFolder = leaf

        #expect(!viewModel.expandSelectedSidebarFolder())
        #expect(!viewModel.isFolderExpanded(leaf))
    }

    private func folder(_ path: String) -> BrowserFolderItem {
        BrowserFolderItem(url: URL(filePath: "/tmp/RawCullFBTests/\(path)", directoryHint: .isDirectory))
    }
}
