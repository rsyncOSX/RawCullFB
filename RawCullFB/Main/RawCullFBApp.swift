import AppKit
import SwiftUI

@main
struct RawCullFBApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var viewModel = FileBrowserViewModel()
    @State private var hasLoadedWorkspace = false

    var body: some Scene {
        Window("RawCullFB", id: "main-window") {
            FileBrowserView(viewModel: viewModel)
                .environment(viewModel)
                .background(.windowBackground)
                .task {
                    guard !hasLoadedWorkspace else { return }
                    hasLoadedWorkspace = true
                    await viewModel.loadSettings()
                    await viewModel.loadRememberedCatalogs()
                }
        }
        .defaultSize(width: 1100, height: 760)
        .windowToolbarStyle(.unified)
        .commands {
            SidebarCommands()
            RawCullFBCommands()
        }

        Window("AI Workspace", id: "ai-workspace") {
            BrowserAIWorkspaceView(viewModel: viewModel)
                .environment(viewModel)
        }
        .defaultSize(width: 1200, height: 780)
        .windowToolbarStyle(.unified)

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
