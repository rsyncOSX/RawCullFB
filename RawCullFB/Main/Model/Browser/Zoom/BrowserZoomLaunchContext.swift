import Foundation

struct BrowserZoomLaunchContext: Equatable {
    var initialZoomMode: BrowserZoomInitialMode
    var showFocusPointOnOpen: Bool

    static let `default` = BrowserZoomLaunchContext(
        initialZoomMode: .fit,
        showFocusPointOnOpen: false,
    )
}
