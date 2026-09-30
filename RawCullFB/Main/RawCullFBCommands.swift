import SwiftUI

struct RawCullFBCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandMenu("Workspace") {
            Button("Image Browser") { openWindow(id: "main-window") }
                .keyboardShortcut("1", modifiers: .command)
            Button("AI Workspace") { openWindow(id: "ai-workspace") }
                .keyboardShortcut("2", modifiers: .command)
        }
        CommandGroup(replacing: .appInfo) {
            Button("About RawCullFB") {
                openWindow(id: "about-window")
            }
        }
    }
}
