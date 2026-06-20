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

    static func save(_ settings: BrowserSettings) async {
        let url = settingsURL

        do {
            let data = try JSONEncoder().encode(settings)
            try await Task.detached(priority: .utility) {
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true,
                )
                try data.write(to: url, options: .atomic)
            }.value
        } catch {
            return
        }
    }

    private static var settingsURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport
            .appendingPathComponent("RawCullFB", isDirectory: true)
            .appendingPathComponent("settings.json")
    }
}
