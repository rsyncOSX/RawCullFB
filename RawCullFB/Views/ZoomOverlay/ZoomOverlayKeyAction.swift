import Foundation

nonisolated enum ZoomOverlayKeyAction: Equatable {
    case navigatePrevious
    case navigateNext
    case escape
    case zoomIn
    case zoomOut
    case toggleFocusPoints
    case inspectActualPixels
    case rating(Int)

    nonisolated static func resolve(
        characters: String?,
        keyCode: UInt16,
        navigationAxis: ZoomOverlayNavigationAxis,
    ) -> ZoomOverlayKeyAction? {
        if let action = action(for: characters) {
            return action
        }

        return switch (navigationAxis, keyCode) {
        case (.horizontal, 123), (.vertical, 126):
            .navigatePrevious

        case (.horizontal, 124), (.vertical, 125):
            .navigateNext

        case (_, 53):
            .escape

        default:
            nil
        }
    }

    private nonisolated static func action(for characters: String?) -> ZoomOverlayKeyAction? {
        switch characters {
        case "+":
            .zoomIn

        case "-":
            .zoomOut

        case "a", "A":
            .toggleFocusPoints

        case "z", "Z":
            .inspectActualPixels

        default:
            BrowserRatingShortcut.rating(for: characters).map(ZoomOverlayKeyAction.rating)
        }
    }
}
