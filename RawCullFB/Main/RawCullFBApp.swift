import AppKit
import SwiftUI

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

        Settings {
            SettingsView()
                .environment(viewModel)
        }

        Window("About RawCullFB", id: "about-window") {
            AboutRawCullFBView()
                .background(.windowBackground)
        }
        .windowResizability(.contentSize)
    }
}
