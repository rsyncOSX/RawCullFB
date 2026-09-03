import BackgroundAssets
import Foundation
import System

nonisolated enum CLIPManagedModel: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case dataComp = "data-comp"
    // case openAI = "openai"

    static let defaultSelection = Self.dataComp

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .dataComp: "DataComp"
        // case .openAI: "OpenAI"
        }
    }

    var downloadID: CLIPModelDownloadID {
        switch self {
        case .dataComp: .clipDataComp
        // case .openAI: .clipOpenAI
        }
    }
}

nonisolated enum CLIPModelDownloadID: String, CaseIterable, Codable, Identifiable, Sendable {
    case clipDataComp = "clip-datacomp"
    // case clipOpenAI = "clip-openai"

    var id: String {
        rawValue
    }

    var model: CLIPManagedModel {
        switch self {
        case .clipDataComp: .dataComp
        // case .clipOpenAI: .openAI
        }
    }
}

nonisolated struct CLIPModelDownloadDescriptor: Equatable, Identifiable, Sendable {
    let id: CLIPModelDownloadID
    let displayName: String
    let purpose: LocalizedStringResource
    let publisher: String
    let modelVersion: String
    let upstreamRevision: String
    let assetPackID: String
    let assetPackModelPath: String
    let modelCardURL: URL
    let licenceName: String
    let licenceSummary: LocalizedStringResource
    let licenceURL: URL
    let downloadByteCount: Int64
}

nonisolated struct CLIPModelDownloadCatalog: Equatable, Sendable {
    let models: [CLIPModelDownloadDescriptor]

    func descriptor(for id: CLIPModelDownloadID) -> CLIPModelDownloadDescriptor? {
        models.first { $0.id == id }
    }

    static let production = Self(models: [
        CLIPModelDownloadDescriptor(
            id: .clipDataComp,
            displayName: "DataComp CLIP",
            purpose: "Image indexing and semantic search.",
            publisher: "LAION / OpenCLIP",
            modelVersion: "ViT-B/32 256px, datacomp_s34b_b86k",
            upstreamRevision: "4afec35ffe57a943d569ff7ee888061830164da8",
            assetPackID: "no.blogspot.RawCull.models.clip-datacomp",
            assetPackModelPath: "Models/CLIP-DataComp",
            modelCardURL: requiredURL(
                "https://huggingface.co/laion/CLIP-ViT-B-32-256x256-DataComp-s34B-b86K",
            ),
            licenceName: "MIT License",
            licenceSummary: "The OpenCLIP/DataComp copyright and permission notice must accompany redistributed copies.",
            licenceURL: requiredURL(
                "https://github.com/mlfoundations/open_clip/blob/main/LICENSE",
            ),
            downloadByteCount: 282_966_632,
        )
    ])

    private static func requiredURL(_ string: String) -> URL {
        guard let url = URL(string: string) else {
            preconditionFailure("Invalid built-in model URL: \(string)")
        }
        return url
    }
}

nonisolated enum CLIPModelDownloadState: Equatable, Sendable {
    case checking
    case notConfigured
    case ready
    case downloading(progress: Double)
    case validating
    case installed(location: URL)
    case removing
    case failed(message: String)

    var installedLocation: URL? {
        guard case let .installed(location) = self else { return nil }
        return location
    }

    var canStartDownload: Bool {
        switch self {
        case .ready, .failed: true
        case .checking, .notConfigured, .downloading, .validating, .installed, .removing: false
        }
    }
}

nonisolated struct CLIPModelDownloadsSnapshot: Equatable, Sendable {
    let states: [CLIPModelDownloadID: CLIPModelDownloadState]
    let managedModelLocations: [CLIPModelDownloadID: URL]
}

nonisolated enum CLIPModelDownloadError: Error, LocalizedError, Sendable {
    case serviceNotConfigured
    case assetPackNotFound(String)
    case downloadedModelNotFound(String)

    var errorDescription: String? {
        switch self {
        case .serviceNotConfigured:
            "The AI model download service has not been configured."

        case let .assetPackNotFound(assetPackID):
            "The model asset pack \(assetPackID) is not present in the download manifest."

        case let .downloadedModelNotFound(path):
            "The downloaded asset pack does not contain the expected model at \(path)."
        }
    }
}

nonisolated protocol CLIPModelDownloadServicing: Sendable {
    func state(for descriptor: CLIPModelDownloadDescriptor) async -> CLIPModelDownloadState
    func download(
        _ descriptor: CLIPModelDownloadDescriptor,
        progress: @escaping @MainActor @Sendable (Double) -> Void,
    ) async throws -> URL
    func remove(_ descriptor: CLIPModelDownloadDescriptor) async throws
}

actor ManagedBackgroundAssetsCLIPModelDownloadService: CLIPModelDownloadServicing {
    static let productionManifestURL = URL(
        string: "https://github.com/rsyncOSX/RawCull-AI-Models/releases/download/v3/manifest.json",
    )!
    static let testManifestURL = URL(
        string: "https://example.invalid/rawcullfb/models/manifest.json",
    )!

    /// Background Assets cannot validate the relocated application bundle used
    /// by Xcode's unit-test runner. Tests use an unconfigured source and inject
    /// a service when they need to exercise transfer behavior.
    static var liveManifestURL: URL {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return testManifestURL
        }
        return productionManifestURL
    }

    private let manifestURL: URL

    init(manifestURL: URL = liveManifestURL) {
        self.manifestURL = manifestURL
    }

    func state(for descriptor: CLIPModelDownloadDescriptor) async -> CLIPModelDownloadState {
        guard isConfigured else { return .notConfigured }

        if AssetPackManager.shared.assetPackIsAvailableLocally(withID: descriptor.assetPackID) {
            do {
                return try .installed(location: modelURL(for: descriptor))
            } catch {
                return .failed(message: String(describing: error))
            }
        }

        do {
            let manifest = try await AssetPackManager.shared.manifest
            guard manifest.assetPack(withID: descriptor.assetPackID) != nil else {
                return .failed(
                    message: CLIPModelDownloadError.assetPackNotFound(
                        descriptor.assetPackID,
                    ).localizedDescription,
                )
            }
            return .ready
        } catch {
            return .failed(message: String(describing: error))
        }
    }

    func download(
        _ descriptor: CLIPModelDownloadDescriptor,
        progress: @escaping @MainActor @Sendable (Double) -> Void,
    ) async throws -> URL {
        guard isConfigured else { throw CLIPModelDownloadError.serviceNotConfigured }
        try Task.checkCancellation()

        let manifest = try await AssetPackManager.shared.manifest
        guard let assetPack = manifest.assetPack(withID: descriptor.assetPackID) else {
            throw CLIPModelDownloadError.assetPackNotFound(descriptor.assetPackID)
        }

        let updates = AssetPackManager.shared.statusUpdates(
            forAssetPackWithID: descriptor.assetPackID,
        )
        let progressTask = Task { @concurrent in
            for await update in updates {
                guard !Task.isCancelled else { return }
                if case let .downloading(_, downloadProgress) = update {
                    await progress(downloadProgress.fractionCompleted)
                }
            }
        }
        defer { progressTask.cancel() }

        try await AssetPackManager.shared.ensureLocalAvailability(
            of: assetPack,
            requireLatestVersion: true,
        )
        try Task.checkCancellation()
        await progress(1)
        return try modelURL(for: descriptor)
    }

    func remove(_ descriptor: CLIPModelDownloadDescriptor) async throws {
        try Task.checkCancellation()
        try await AssetPackManager.shared.remove(assetPackWithID: descriptor.assetPackID)
    }

    private var isConfigured: Bool {
        manifestURL.scheme?.lowercased() == "https"
            && manifestURL.host?.lowercased().hasSuffix(".invalid") == false
    }

    private nonisolated func modelURL(for descriptor: CLIPModelDownloadDescriptor) throws -> URL {
        let url = try AssetPackManager.shared.url(for: FilePath(descriptor.assetPackModelPath))
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: url.path,
            isDirectory: &isDirectory,
        ), isDirectory.boolValue else {
            throw CLIPModelDownloadError.downloadedModelNotFound(
                descriptor.assetPackModelPath,
            )
        }
        return url
    }
}

actor CLIPModelDownloadCoordinator {
    private let catalog: CLIPModelDownloadCatalog
    private let service: any CLIPModelDownloadServicing

    init(
        catalog: CLIPModelDownloadCatalog = .production,
        service: any CLIPModelDownloadServicing = ManagedBackgroundAssetsCLIPModelDownloadService(),
    ) {
        self.catalog = catalog
        self.service = service
    }

    func snapshot() async -> CLIPModelDownloadsSnapshot {
        var states: [CLIPModelDownloadID: CLIPModelDownloadState] = [:]
        var locations: [CLIPModelDownloadID: URL] = [:]

        for descriptor in catalog.models {
            let state = await service.state(for: descriptor)
            states[descriptor.id] = state
            if let location = state.installedLocation {
                locations[descriptor.id] = location
            }
        }
        return CLIPModelDownloadsSnapshot(
            states: states,
            managedModelLocations: locations,
        )
    }

    func download(
        _ id: CLIPModelDownloadID,
        progress: @escaping @MainActor @Sendable (Double) -> Void,
    ) async throws -> URL {
        try await service.download(requiredDescriptor(for: id), progress: progress)
    }

    func remove(_ id: CLIPModelDownloadID) async throws {
        try await service.remove(requiredDescriptor(for: id))
    }

    private func requiredDescriptor(for id: CLIPModelDownloadID) throws -> CLIPModelDownloadDescriptor {
        guard let descriptor = catalog.descriptor(for: id) else {
            throw CLIPModelDownloadError.assetPackNotFound(id.rawValue)
        }
        return descriptor
    }
}
