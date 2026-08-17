@testable import RawCullFB
import Testing

@Suite("Zoom overlay keyboard navigation")
struct ZoomOverlayKeyboardNavigationTests {
    @Test(arguments: ["x", "X"])
    func `X closes the zoom overlay`(characters: String) {
        let action = ZoomOverlayKeyAction.resolve(
            characters: characters,
            keyCode: 0,
            navigationAxis: .horizontal,
        )

        #expect(action == .escape)
    }
}
