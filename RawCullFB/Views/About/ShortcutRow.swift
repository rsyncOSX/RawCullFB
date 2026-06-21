import Foundation

struct ShortcutRow: Identifiable {
    let context: String
    let keys: String
    let action: String

    var id: String {
        "\(context)-\(keys)-\(action)"
    }
}
