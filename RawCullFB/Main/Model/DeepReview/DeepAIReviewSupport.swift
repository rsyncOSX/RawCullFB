import Foundation

nonisolated enum RawCullAICapabilityStatus: Equatable, Sendable {
    case checking(expectedLocations: [URL])
    case available(location: URL?)
    case missing(expectedLocations: [URL])
    case invalid(location: URL?, reason: String)
    case unavailable(reason: String)

    var isAvailable: Bool {
        if case .available = self {
            true
        } else {
            false
        }
    }
}

nonisolated struct BurstGroupSignature: Codable, Hashable, Sendable {
    let memberKeys: [String]

    init(memberKeys: [String]) {
        self.memberKeys = memberKeys
            .filter { !$0.isEmpty }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    init(files: [BrowserFileItem], catalog: URL?) {
        let keys = files.map { Self.memberKey(for: $0, catalog: catalog) }
        self.init(memberKeys: keys)
    }

    static func memberKey(for file: BrowserFileItem, catalog: URL?) -> String {
        guard let catalog else { return file.name }

        let catalogPath = catalog.standardizedFileURL.path
        let filePath = file.url.standardizedFileURL.path
        let prefix = catalogPath.hasSuffix("/") ? catalogPath : catalogPath + "/"

        guard filePath.hasPrefix(prefix) else { return file.name }
        let relativePath = String(filePath.dropFirst(prefix.count))
        return relativePath.isEmpty ? file.name : relativePath
    }
}

nonisolated enum SharpnessScoringSource: String, CaseIterable, Codable, Identifiable, Sendable {
    case embeddedPreview
    case rawDemosaic

    var id: String {
        rawValue
    }
}
