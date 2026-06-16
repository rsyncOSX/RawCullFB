import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        true
    }
}

@main
struct RawCullFBApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var viewModel = FileBrowserViewModel()

    var body: some Scene {
        Window("RawCullFB", id: "main-window") {
            FileBrowserView(viewModel: viewModel)
                .environment(viewModel)
                .background(.windowBackground)
                .task {
                    await viewModel.loadSettings()
                    await viewModel.loadRememberedCatalogs()
                }
                .onDisappear {
                    viewModel.stopActiveSecurityScopedAccess()
                    NSApplication.shared.terminate(nil)
                }
        }
        .windowToolbarStyle(.unified)
        .commands {
            SidebarCommands()
            RawCullFBCommands()
        }

        Window("About RawCullFB", id: "about-window") {
            AboutRawCullFBView()
                .background(.windowBackground)
        }
        .windowResizability(.contentSize)
    }
}

private struct RawCullFBCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About RawCullFB") {
                openWindow(id: "about-window")
            }
        }
    }
}
