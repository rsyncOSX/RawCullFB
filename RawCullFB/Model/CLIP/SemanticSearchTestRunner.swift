import Foundation

nonisolated struct SemanticSearchTestProgress: Equatable, Sendable {
    let completedQueryCount: Int
    let totalQueryCount: Int
    let currentQuery: String?
    let resultFileURL: URL
}

nonisolated struct SemanticSearchTestOutcome: Equatable, Sendable {
    let completedQueryCount: Int
    let totalQueryCount: Int
    let resultFileURL: URL
    let wasCancelled: Bool
}

nonisolated enum SemanticSearchTestRunnerError: Error, LocalizedError, Sendable {
    case missingInputFile(URL)
    case unreadableInputFile(URL)
    case noQueries(URL)

    var errorDescription: String? {
        switch self {
        case let .missingInputFile(url):
            "Semantic test input was not found at \(url.path)."
        case let .unreadableInputFile(url):
            "Semantic test input is not valid UTF-8 text: \(url.path)."
        case let .noQueries(url):
            "Semantic test input contains no queries: \(url.path)."
        }
    }
}

nonisolated enum SemanticSearchTestRunner {
    static let inputFileName = "semantictest.txt"

    typealias Search = @Sendable (String, Int) async throws -> [CLIPSearchResult]
    typealias Progress = @Sendable (SemanticSearchTestProgress) async -> Void

    static func run(
        directory: URL,
        modelName: String,
        modelFingerprint: String,
        resultLimit: Int,
        search: Search,
        progress: Progress? = nil,
    ) async throws -> SemanticSearchTestOutcome {
        let catalogURL = directory.standardizedFileURL
        let inputURL = catalogURL.appendingPathComponent(inputFileName)
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            throw SemanticSearchTestRunnerError.missingInputFile(inputURL)
        }
        guard let input = try? String(contentsOf: inputURL, encoding: .utf8) else {
            throw SemanticSearchTestRunnerError.unreadableInputFile(inputURL)
        }

        let queries = input.components(separatedBy: .newlines).compactMap { line -> String? in
            let query = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty, !query.hasPrefix("#") else { return nil }
            return query
        }
        guard !queries.isEmpty else {
            throw SemanticSearchTestRunnerError.noQueries(inputURL)
        }

        let resultFileURL = catalogURL.appendingPathComponent(
            "\(safeFileName(modelName))-semantic-test-results.txt",
        )
        let startedAt = Date()
        var records: [QueryRecord] = []
        var wasCancelled = false

        try writeReport(
            to: resultFileURL,
            modelName: modelName,
            modelFingerprint: modelFingerprint,
            catalogURL: catalogURL,
            resultLimit: resultLimit,
            startedAt: startedAt,
            status: "running",
            totalQueryCount: queries.count,
            records: records,
        )
        await progress?(SemanticSearchTestProgress(
            completedQueryCount: 0,
            totalQueryCount: queries.count,
            currentQuery: queries.first,
            resultFileURL: resultFileURL,
        ))

        for query in queries {
            if Task.isCancelled {
                wasCancelled = true
                break
            }

            let queryStartedAt = Date()
            do {
                let results = try await search(query, resultLimit)
                records.append(QueryRecord(
                    query: query,
                    durationMilliseconds: elapsedMilliseconds(since: queryStartedAt),
                    results: results,
                    error: nil,
                ))
            } catch is CancellationError {
                wasCancelled = true
                break
            } catch {
                records.append(QueryRecord(
                    query: query,
                    durationMilliseconds: elapsedMilliseconds(since: queryStartedAt),
                    results: [],
                    error: String(describing: error),
                ))
            }

            try writeReport(
                to: resultFileURL,
                modelName: modelName,
                modelFingerprint: modelFingerprint,
                catalogURL: catalogURL,
                resultLimit: resultLimit,
                startedAt: startedAt,
                status: records.count == queries.count ? "completed" : "running",
                totalQueryCount: queries.count,
                records: records,
            )
            await progress?(SemanticSearchTestProgress(
                completedQueryCount: records.count,
                totalQueryCount: queries.count,
                currentQuery: records.count < queries.count ? queries[records.count] : nil,
                resultFileURL: resultFileURL,
            ))
        }

        try writeReport(
            to: resultFileURL,
            modelName: modelName,
            modelFingerprint: modelFingerprint,
            catalogURL: catalogURL,
            resultLimit: resultLimit,
            startedAt: startedAt,
            status: wasCancelled ? "cancelled" : "completed",
            totalQueryCount: queries.count,
            records: records,
        )

        return SemanticSearchTestOutcome(
            completedQueryCount: records.count,
            totalQueryCount: queries.count,
            resultFileURL: resultFileURL,
            wasCancelled: wasCancelled,
        )
    }

    private struct QueryRecord {
        let query: String
        let durationMilliseconds: Int
        let results: [CLIPSearchResult]
        let error: String?
    }

    private static func writeReport(
        to url: URL,
        modelName: String,
        modelFingerprint: String,
        catalogURL: URL,
        resultLimit: Int,
        startedAt: Date,
        status: String,
        totalQueryCount: Int,
        records: [QueryRecord],
    ) throws {
        var lines = [
            "RawCullFB semantic search test",
            "model\t\(tabSafe(modelName))",
            "model_fingerprint\t\(tabSafe(modelFingerprint))",
            "catalog\t\(tabSafe(catalogURL.path))",
            "started_at\t\(ISO8601DateFormatter().string(from: startedAt))",
            "updated_at\t\(ISO8601DateFormatter().string(from: Date()))",
            "status\t\(status)",
            "result_limit\t\(resultLimit)",
            "completed_queries\t\(records.count)",
            "total_queries\t\(totalQueryCount)",
            "",
        ]

        for (offset, record) in records.enumerated() {
            lines.append("QUERY\t\(offset + 1)\t\(tabSafe(record.query))")
            lines.append("duration_ms\t\(record.durationMilliseconds)")
            if let error = record.error {
                lines.append("error\t\(tabSafe(error))")
            } else {
                lines.append("rank\tscore\tfile\tpath")
                for result in record.results {
                    lines.append(
                        "\(result.rank)\t\(result.score)\t\(tabSafe(result.fileName))\t\(tabSafe(relativePath(result.path, catalogURL: catalogURL)))",
                    )
                }
            }
            lines.append("")
        }

        try Data((lines.joined(separator: "\n") + "\n").utf8).write(
            to: url,
            options: .atomic,
        )
    }

    private static func elapsedMilliseconds(since date: Date) -> Int {
        max(0, Int(Date().timeIntervalSince(date) * 1_000))
    }

    private static func relativePath(_ path: String, catalogURL: URL) -> String {
        let catalogPath = catalogURL.path.hasSuffix("/")
            ? catalogURL.path
            : catalogURL.path + "/"
        guard path.hasPrefix(catalogPath) else { return path }
        return String(path.dropFirst(catalogPath.count))
    }

    private static func safeFileName(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let scalars = value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? String(scalar) : "-"
        }
        let collapsed = scalars.joined().replacingOccurrences(
            of: "-+",
            with: "-",
            options: .regularExpression,
        )
        return collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private static func tabSafe(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
    }
}
