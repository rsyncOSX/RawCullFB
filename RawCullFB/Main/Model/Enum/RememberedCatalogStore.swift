import Foundation

enum RememberedCatalogStore {
    static func load() async -> [RememberedCatalog] {
        let url = catalogsURL

        guard FileManager.default.fileExists(atPath: url.path) else {
            print("Catalog file does not exist")
            return []
        }

        do {
            let data = try await Task.detached(priority: .utility) {
                try Data(contentsOf: url)
            }.value

            return try JSONDecoder.catalogDecoder.decode(
                [RememberedCatalog].self,
                from: data,
            )
        } catch {
            return []
        }
    }

    static func catalog(for url: URL) -> RememberedCatalog? {
        let bookmarkData = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil,
        )

        return RememberedCatalog(
            path: url.path,
            bookmarkData: bookmarkData,
        )
    }

    static func save(_ catalogs: [RememberedCatalog]) async {
        await saveCatalogs(catalogs)
    }

    static func clear() async {
        let url = catalogsURL
        await Task.detached(priority: .utility) {
            try? FileManager.default.removeItem(at: url)
        }.value
    }

    static func resolvedURL(for catalog: RememberedCatalog) -> URL? {
        if let bookmarkData = catalog.bookmarkData {
            var isStale = false
            return (try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale,
            )) ?? URL(filePath: catalog.path)
        }

        return URL(filePath: catalog.path)
    }

    private static func saveCatalogs(_ catalogs: [RememberedCatalog]) async {
        let url = catalogsURL
        do {
            let data = try JSONEncoder.prettyCatalogEncoder.encode(catalogs)
            try await Task.detached(priority: .utility) {
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true,
                )
                try data.write(to: url, options: [.atomic])
            }.value
        } catch {
            return
        }
    }

    private static var catalogsURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport
            .appendingPathComponent("RawCullFB", isDirectory: true)
            .appendingPathComponent("catalogs.json")
    }
}

private extension JSONEncoder {
    static var prettyCatalogEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var catalogDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
