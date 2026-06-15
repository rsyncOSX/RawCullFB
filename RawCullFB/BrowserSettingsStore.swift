import Foundation

enum BrowserSettingsStore {
    static func load() async -> BrowserSettings {
        let url = settingsURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            return BrowserSettings()
        }

        do {
            let data = try await Task.detached(priority: .utility) {
                try Data(contentsOf: url)
            }.value
            return try JSONDecoder().decode(BrowserSettings.self, from: data)
        } catch {
            return BrowserSettings()
        }
    }

    private static var settingsURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport
            .appendingPathComponent("RawCull", isDirectory: true)
            .appendingPathComponent("settings.json")
    }
}
