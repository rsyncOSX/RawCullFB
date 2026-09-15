import CoreAIImageSegmenter
import Foundation
import PhotoAIContracts

/// Validated, model-specific runtime configuration for a CLIP bundle.
///
/// New bundles should describe every field in `metadata.json`. Legacy
/// PhotoAIKit bundles continue to use the OpenAI ViT-B/32 defaults.
public struct CLIPRuntimeConfiguration: Equatable, Sendable {
    public let sourceModel: String?
    public let sourceRevision: String?
    public let architecture: String
    public let pretrained: String?
    public let embeddingDimensions: Int?
    public let preprocessing: ModelImagePreprocessingMetadata
    public let tokenizer: ModelTokenizerMetadata
    public let imageFunctionName: String
    public let textFunctionName: String
    public let normalizationVersion: String
    public let configurationVersion: String

    init(metadata: ModelBundleMetadata) throws {
        let preprocessing = metadata.preprocessing ?? Self.legacyPreprocessing(
            version: metadata.preprocessingVersion
                ?? ModelResourceDescriptor.clip.preprocessingVersion
        )
        let tokenizer = metadata.tokenizer ?? ModelTokenizerMetadata(
            version: CoreAICLIPProvider.tokenizerVersion,
            type: "clip-bpe",
            contextLength: 77
        )

        let isCenterCrop = preprocessing.resize == "shortest-side"
            && preprocessing.crop == "center"
            && preprocessing.interpolation == "bicubic"
        let isLegacyStretch = preprocessing.resize == "stretch"
            && preprocessing.crop == "none"
            && preprocessing.interpolation == "bilinear"
        guard preprocessing.width > 0,
              preprocessing.height > 0,
              isCenterCrop || isLegacyStretch,
              !isCenterCrop
                  || preprocessing.width == preprocessing.height,
              preprocessing.mean.count == 3,
              preprocessing.standardDeviation.count == 3,
              preprocessing.mean.allSatisfy(\.isFinite),
              preprocessing.standardDeviation.allSatisfy({
                  $0.isFinite && $0 > 0
              })
        else {
            throw CLIPProviderError.invalidModel(
                "CLIP preprocessing metadata is missing or unsupported."
            )
        }
        let supportedTokenizerTypes = ["clip-bpe", "huggingface-tokenizer-json"]
        guard tokenizer.contextLength > 1,
              supportedTokenizerTypes.contains(tokenizer.type),
              !tokenizer.version.isEmpty,
              (tokenizer.paddingTokenID ?? CoreAIClipTokenizer.eotTokenId) >= 0
        else {
            throw CLIPProviderError.invalidModel(
                "CLIP tokenizer metadata is missing or unsupported."
            )
        }

        self.sourceModel = metadata.sourceModel
        self.sourceRevision = metadata.sourceRevision
        self.architecture = metadata.architecture ?? "ViT-B-32"
        self.pretrained = metadata.pretrained
        self.embeddingDimensions = metadata.embeddingDimensions
        self.preprocessing = preprocessing
        self.tokenizer = tokenizer
        self.imageFunctionName = metadata.functions?["image"] ?? "main"
        self.textFunctionName = metadata.functions?["text"] ?? "main"
        self.normalizationVersion = metadata.normalizationVersion ?? "l2-v1"
        self.configurationVersion = metadata.configurationVersion
            ?? ModelResourceDescriptor.clip.configurationVersion
    }

    private static func legacyPreprocessing(
        version: String
    ) -> ModelImagePreprocessingMetadata {
        ModelImagePreprocessingMetadata(
            version: version,
            width: 224,
            height: 224,
            resize: "stretch",
            crop: "none",
            interpolation: "bilinear",
            mean: [0.48145466, 0.4578275, 0.40821073],
            standardDeviation: [0.26862954, 0.26130258, 0.27577711]
        )
    }
}
