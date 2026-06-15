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
                }
                .onDisappear {
                    viewModel.stopActiveSecurityScopedAccess()
                    NSApplication.shared.terminate(nil)
                }
        }
        .windowToolbarStyle(.unified)
        .commands {
            SidebarCommands()
        }
    }
}
