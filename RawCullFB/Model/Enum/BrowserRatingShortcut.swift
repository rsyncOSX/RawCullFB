import Foundation

nonisolated enum BrowserRatingShortcut {
    nonisolated static func rating(for characters: String?) -> Int? {
        switch characters {
        case "x", "X":
            -1

        case "p", "P", "0":
            0

        case "1", "2":
            2

        case "3", "t", "T":
            3

        case "4":
            4

        case "5":
            5

        default:
            nil
        }
    }
}
