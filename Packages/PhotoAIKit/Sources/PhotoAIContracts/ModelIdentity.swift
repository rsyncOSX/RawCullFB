import Foundation

/// Stable identity for a model bundle supplied by a host application.
public struct ModelIdentity: Codable, Hashable, Sendable {
    public let family: String
    public let name: String
    public let sourceModel: String?
    public let assetName: String
    public let metadataVersion: String?
    public let assetFingerprint: ModelAssetFingerprint?
    private let cacheIdentifierOverride: String?

    public init(
        family: String,
        name: String,
        sourceModel: String? = nil,
        assetName: String,
        metadataVersion: String? = nil,
        cacheIdentifier: String? = nil
    ) {
        self.init(
            family: family,
            name: name,
            sourceModel: sourceModel,
            assetName: assetName,
            metadataVersion: metadataVersion,
            assetFingerprint: nil,
            cacheIdentifier: cacheIdentifier
        )
    }

    public init(
        family: String,
        name: String,
        sourceModel: String? = nil,
        assetName: String,
        metadataVersion: String? = nil,
        assetFingerprint: ModelAssetFingerprint?,
        cacheIdentifier: String? = nil
    ) {
        self.family = family
        self.name = name
        self.sourceModel = sourceModel
        self.assetName = assetName
        self.metadataVersion = metadataVersion
        self.assetFingerprint = assetFingerprint
        self.cacheIdentifierOverride = cacheIdentifier
    }

    public var cacheIdentifier: String {
        if let cacheIdentifierOverride {
            return cacheIdentifierOverride
        }
        if family.lowercased() == "sam3" {
            return "coreai-sam3-local:\(name):\(assetName)"
        }
        return [family, name, sourceModel ?? "", assetName, metadataVersion ?? ""]
            .joined(separator: ":")
    }

    /// Fingerprinted identity for new persisted artifacts and caches. The
    /// existing `cacheIdentifier` remains source- and behavior-compatible for
    /// hosts that have not migrated yet.
    public var artifactIdentifier: String {
        guard let assetFingerprint else { return cacheIdentifier }
        return "\(cacheIdentifier):\(assetFingerprint.cacheIdentifier)"
    }
}

public struct ModelBundleMetadata: Codable, Equatable, Sendable {
    public let name: String?
    public let family: String?
    public let sourceModel: String?
    public let sourceRevision: String?
    public let architecture: String?
    public let pretrained: String?
    public let metadataVersion: String?
    public let embeddingDimensions: Int?
    public let assets: [String: String]
    public let assetFingerprints: [String: ModelAssetFingerprintManifest]?
    public let preprocessingVersion: String?
    public let preprocessing: ModelImagePreprocessingMetadata?
    public let tokenizer: ModelTokenizerMetadata?
    public let functions: [String: String]?
    public let normalizationVersion: String?
    public let configurationVersion: String?

    public init(
        name: String? = nil,
        family: String? = nil,
        sourceModel: String? = nil,
        metadataVersion: String? = nil,
        assets: [String: String]
    ) {
        self.init(
            name: name,
            family: family,
            sourceModel: sourceModel,
            sourceRevision: nil,
            architecture: nil,
            pretrained: nil,
            metadataVersion: metadataVersion,
            embeddingDimensions: nil,
            assets: assets,
            assetFingerprints: nil,
            preprocessingVersion: nil,
            preprocessing: nil,
            tokenizer: nil,
            functions: nil,
            normalizationVersion: nil,
            configurationVersion: nil
        )
    }

    public init(
        name: String? = nil,
        family: String? = nil,
        sourceModel: String? = nil,
        sourceRevision: String? = nil,
        architecture: String? = nil,
        pretrained: String? = nil,
        metadataVersion: String? = nil,
        embeddingDimensions: Int? = nil,
        assets: [String: String],
        assetFingerprints: [String: ModelAssetFingerprintManifest]?,
        preprocessingVersion: String? = nil,
        preprocessing: ModelImagePreprocessingMetadata? = nil,
        tokenizer: ModelTokenizerMetadata? = nil,
        functions: [String: String]? = nil,
        normalizationVersion: String? = nil,
        configurationVersion: String? = nil
    ) {
        self.name = name
        self.family = family
        self.sourceModel = sourceModel
        self.sourceRevision = sourceRevision
        self.architecture = architecture
        self.pretrained = pretrained
        self.metadataVersion = metadataVersion
        self.embeddingDimensions = embeddingDimensions
        self.assets = assets
        self.assetFingerprints = assetFingerprints
        self.preprocessingVersion = preprocessingVersion
        self.preprocessing = preprocessing
        self.tokenizer = tokenizer
        self.functions = functions
        self.normalizationVersion = normalizationVersion
        self.configurationVersion = configurationVersion
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case family
        case sourceModel = "source_model"
        case sourceRevision = "source_revision"
        case architecture
        case pretrained
        case metadataVersion = "metadata_version"
        case embeddingDimensions = "embedding_dimensions"
        case assets
        case assetFingerprints = "asset_fingerprints"
        case preprocessingVersion = "preprocessing_version"
        case preprocessing
        case tokenizer
        case functions
        case normalizationVersion = "normalization_version"
        case configurationVersion = "configuration_version"
    }
}

public struct ModelImagePreprocessingMetadata: Codable, Equatable, Sendable {
    public let version: String
    public let width: Int
    public let height: Int
    public let resize: String
    public let crop: String
    public let interpolation: String
    public let mean: [Float]
    public let standardDeviation: [Float]

    public init(
        version: String,
        width: Int,
        height: Int,
        resize: String,
        crop: String,
        interpolation: String,
        mean: [Float],
        standardDeviation: [Float]
    ) {
        self.version = version
        self.width = width
        self.height = height
        self.resize = resize
        self.crop = crop
        self.interpolation = interpolation
        self.mean = mean
        self.standardDeviation = standardDeviation
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case width
        case height
        case resize
        case crop
        case interpolation
        case mean
        case standardDeviation = "standard_deviation"
    }
}

public struct ModelTokenizerMetadata: Codable, Equatable, Sendable {
    public let version: String
    public let type: String
    public let contextLength: Int
    public let paddingTokenID: Int32?

    public init(
        version: String,
        type: String,
        contextLength: Int,
        paddingTokenID: Int32? = nil
    ) {
        self.version = version
        self.type = type
        self.contextLength = contextLength
        self.paddingTokenID = paddingTokenID
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case type
        case contextLength = "context_length"
        case paddingTokenID = "padding_token_id"
    }
}
