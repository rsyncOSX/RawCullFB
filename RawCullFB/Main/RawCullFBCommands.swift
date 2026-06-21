import SwiftUI

struct RawCullFBCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About RawCullFB") {
                openWindow(id: "about-window")
            }
        }
    }
}
