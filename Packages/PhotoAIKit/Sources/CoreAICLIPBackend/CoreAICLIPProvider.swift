import CoreAI
import CoreAIImageSegmenter
import CoreGraphics
import Foundation
import PhotoAIContracts
import Tokenizers

/// Actor-owned Core AI CLIP runtime. The host supplies the model bundle URL.
public actor CoreAICLIPProvider:
    ImageEmbeddingProviding,
    ImageSimilarityArtifactProviding,
    ImageSimilarityArtifactComparing,
    TextEmbeddingProviding,
    ImageTextSimilarityComparing
{
    public nonisolated let modelIdentity: ModelIdentity
    public nonisolated let runtimeConfiguration: CLIPRuntimeConfiguration

    public nonisolated static let resourceDescriptor = ModelResourceDescriptor.clip
    public nonisolated static let tokenizerVersion = "clip-bpe-tokenizer-v1"
    public nonisolated static let pillowBicubicPreprocessingVersion =
        "photoaikit-pillow-bicubic-v1"

    public nonisolated var semanticBackend: String {
        modelIdentity.family.lowercased() == "siglip2" ? "siglip2" : "clip"
    }

    public nonisolated static var factory: ModelProviderFactory<CoreAICLIPProvider> {
        ModelProviderFactory(descriptor: resourceDescriptor) { url in
            try CoreAICLIPProvider(modelBundleURL: url)
        }
    }

    public nonisolated var backendDescriptor: SimilarityBackendDescriptor {
        SimilarityBackendDescriptor(
            backend: semanticBackend,
            modelFingerprint: modelIdentity.artifactIdentifier,
            representation: "normalized-float-vector-json-v1",
            preprocessingVersion: effectivePreprocessingVersion,
            normalizationVersion: runtimeConfiguration.normalizationVersion,
            configurationVersion: runtimeConfiguration.configurationVersion
        )
    }

    private nonisolated var effectivePreprocessingVersion: String {
        Self.effectivePreprocessingVersion(
            for: runtimeConfiguration.preprocessing
        )
    }

    nonisolated static func effectivePreprocessingVersion(
        for preprocessing: ModelImagePreprocessingMetadata
    ) -> String {
        guard preprocessing.resize == "shortest-side",
              preprocessing.crop == "center",
              preprocessing.interpolation == "bicubic"
        else { return preprocessing.version }
        return "\(preprocessing.version):\(Self.pillowBicubicPreprocessingVersion)"
    }

    private let modelBundleURL: URL
    private var loadedModel: LoadedCLIPModel?

    public init(modelBundleURL: URL) throws {
        let resolver = ModelBundleResolver(descriptor: Self.resourceDescriptor.bundleDescriptor)
        guard case let .valid(_, identity) = resolver.status(at: modelBundleURL) else {
            throw CLIPProviderError.invalidModelBundle(resolver.status(at: modelBundleURL))
        }
        let metadataURL = modelBundleURL.appendingPathComponent("metadata.json")
        let metadata = try JSONDecoder().decode(
            ModelBundleMetadata.self,
            from: Data(contentsOf: metadataURL)
        )
        self.modelBundleURL = modelBundleURL
        self.modelIdentity = identity
        self.runtimeConfiguration = try CLIPRuntimeConfiguration(metadata: metadata)
    }

    public func embedding(for image: CGImage) async throws -> ImageEmbedding {
        let model = try await loadModel()
        let values = try await imageEmbedding(for: image, model: model)
        return ImageEmbedding(
            backend: semanticBackend,
            modelIdentity: modelIdentity,
            values: values
        )
    }

    public func embedding(for text: String) async throws -> TextEmbedding {
        try Task.checkCancellation()
        let model = try await loadModel()
        try Task.checkCancellation()

        let sequenceLength = model.inputIDsDescriptor.shape[1]
        let paddingTokenID = runtimeConfiguration.tokenizer.paddingTokenID
            ??             CoreAIClipTokenizer.eotTokenId
        let terminalTokenID = model.tokenizer.eosTokenID
        let queryTokens = model.tokenizer.encode(
            text,
            contextLength: sequenceLength,
            paddingTokenID: paddingTokenID
        )
        let batch = try Self.makeTextBatch(
            queryTokens: queryTokens,
            fillerTokens: model.dummyTokens[0],
            batchSize: model.inputIDsDescriptor.shape[0],
            sequenceLength: sequenceLength,
            paddingTokenID: paddingTokenID,
            terminalTokenID: terminalTokenID
        )

        try Task.checkCancellation()
        let values = try await textEmbedding(for: batch, model: model)
        try Task.checkCancellation()

        do {
            return try TextEmbedding(
                descriptor: TextEmbeddingDescriptor(
                    backend: backendDescriptor,
                    dimensions: values.count,
                    tokenizerVersion: runtimeConfiguration.tokenizer.version
                ),
                values: values
            )
        } catch let error as TextEmbeddingValidationError {
            throw CLIPTextInferenceError.invalidEmbedding(error)
        }
    }

    public func artifact(
        for image: CGImage,
        source: AIImageSource
    ) async throws -> SimilarityArtifact {
        let embedding = try await embedding(for: image)
        return SimilarityArtifact(
            descriptor: SimilarityArtifactDescriptor(
                backend: backendDescriptor,
                dimensions: embedding.values.count,
                sourceFingerprint: SourceFingerprint(source: source)
            ),
            payload: try JSONEncoder().encode(embedding)
        )
    }

    public nonisolated func distance(
        from left: SimilarityArtifact,
        to right: SimilarityArtifact
    ) throws -> Float? {
        guard left.descriptor.isCompatibleForDistance(with: right.descriptor),
              left.descriptor.backend == backendDescriptor.backend,
              left.descriptor.modelFingerprint == backendDescriptor.modelFingerprint
        else { return nil }
        do {
            let decoder = JSONDecoder()
            let leftEmbedding = try decoder.decode(ImageEmbedding.self, from: left.payload)
            let rightEmbedding = try decoder.decode(ImageEmbedding.self, from: right.payload)
            guard EmbeddingArtifact(
                descriptor: left.descriptor,
                embedding: leftEmbedding
            ).isInternallyConsistent,
            EmbeddingArtifact(
                descriptor: right.descriptor,
                embedding: rightEmbedding
            ).isInternallyConsistent else {
                throw CLIPSimilarityArtifactError.invalidPayload(
                    "The vector payload does not match its artifact descriptor."
                )
            }
            return leftEmbedding.cosineDistance(to: rightEmbedding)
        } catch let error as CLIPSimilarityArtifactError {
            throw error
        } catch {
            throw CLIPSimilarityArtifactError.invalidPayload(String(describing: error))
        }
    }

    public nonisolated func similarity(
        image: SimilarityArtifact,
        text: TextEmbedding
    ) throws -> Float {
        let validatedText: TextEmbedding
        do {
            validatedText = try text.validated()
        } catch let error as TextEmbeddingValidationError {
            throw ImageTextSimilarityError.invalidTextEmbedding(error)
        }

        let imageDescriptor = image.descriptor
        let textDescriptor = validatedText.descriptor
        guard imageDescriptor.backend == backendDescriptor.backend else {
            throw ImageTextSimilarityError.unsupportedImageBackend(
                expected: backendDescriptor.backend,
                actual: imageDescriptor.backend
            )
        }
        guard textDescriptor.backend.backend == backendDescriptor.backend else {
            throw ImageTextSimilarityError.unsupportedTextBackend(
                expected: backendDescriptor.backend,
                actual: textDescriptor.backend.backend
            )
        }
        guard imageDescriptor.modelFingerprint == backendDescriptor.modelFingerprint,
              textDescriptor.backend.modelFingerprint == backendDescriptor.modelFingerprint
        else {
            throw ImageTextSimilarityError.incompatibleModelFingerprint
        }
        guard imageDescriptor.dimensions == textDescriptor.dimensions else {
            throw ImageTextSimilarityError.incompatibleDimensions(
                expected: textDescriptor.dimensions,
                actual: imageDescriptor.dimensions
            )
        }
        guard imageDescriptor.representation == backendDescriptor.representation,
              textDescriptor.backend.representation == backendDescriptor.representation
        else {
            throw ImageTextSimilarityError.incompatibleRepresentation
        }
        guard imageDescriptor.preprocessingVersion == backendDescriptor.preprocessingVersion,
              textDescriptor.backend.preprocessingVersion == backendDescriptor.preprocessingVersion
        else {
            throw ImageTextSimilarityError.incompatiblePreprocessing
        }
        guard imageDescriptor.normalizationVersion == backendDescriptor.normalizationVersion,
              textDescriptor.backend.normalizationVersion == backendDescriptor.normalizationVersion
        else {
            throw ImageTextSimilarityError.incompatibleNormalization
        }
        guard imageDescriptor.configurationVersion == backendDescriptor.configurationVersion,
              textDescriptor.backend.configurationVersion == backendDescriptor.configurationVersion
        else {
            throw ImageTextSimilarityError.incompatibleConfiguration
        }
        guard textDescriptor.tokenizerVersion == runtimeConfiguration.tokenizer.version else {
            throw ImageTextSimilarityError.incompatibleTokenizer
        }
        guard imageDescriptor.schemaVersion == SimilarityArtifactDescriptor.currentSchemaVersion else {
            throw ImageTextSimilarityError.invalidImageSchemaVersion(imageDescriptor.schemaVersion)
        }

        let imageEmbedding: ImageEmbedding
        do {
            imageEmbedding = try JSONDecoder().decode(ImageEmbedding.self, from: image.payload)
        } catch {
            throw ImageTextSimilarityError.invalidImagePayload(String(describing: error))
        }
        guard EmbeddingArtifact(
            descriptor: imageDescriptor,
            embedding: imageEmbedding
        ).isInternallyConsistent else {
            throw ImageTextSimilarityError.invalidImagePayload(
                "The vector payload does not match its artifact descriptor."
            )
        }
        guard imageEmbedding.values.allSatisfy(\.isFinite) else {
            throw ImageTextSimilarityError.invalidImagePayload(
                "The image vector contains a non-finite value."
            )
        }
        let squaredMagnitude = imageEmbedding.values.reduce(Float.zero) {
            $0 + $1 * $1
        }
        guard squaredMagnitude.isFinite, squaredMagnitude > 0 else {
            throw ImageTextSimilarityError.invalidImagePayload(
                "The image vector has zero or invalid magnitude."
            )
        }
        let magnitude = sqrt(squaredMagnitude)
        guard abs(magnitude - 1) <= TextEmbedding.normalizationTolerance else {
            throw ImageTextSimilarityError.invalidImagePayload(
                "The image vector is not L2-normalized."
            )
        }

        let similarity = zip(imageEmbedding.values, validatedText.values)
            .reduce(Float.zero) { $0 + $1.0 * $1.1 }
        guard similarity.isFinite else {
            throw ImageTextSimilarityError.invalidImagePayload(
                "The image/text similarity is not finite."
            )
        }
        return max(-1, min(1, similarity))
    }

    private func imageEmbedding(for image: CGImage, model: LoadedCLIPModel) async throws -> [Float] {
        let imageInput = try Self.makeImageInput(
            image,
            descriptor: model.imageDescriptor,
            preprocessing: runtimeConfiguration.preprocessing
        )
        var inputs = [model.imageInputName: imageInput]
        if model.imageFunctionRequiresTextInputs {
            inputs[model.inputIDsInputName] = Self.makeTokenInput(
                model.dummyTokens,
                descriptor: model.inputIDsDescriptor
            )
            if let attentionMaskDescriptor = model.attentionMaskDescriptor,
               let attentionMaskInputName = model.attentionMaskInputName {
                inputs[attentionMaskInputName] = Self.makeAttentionMaskInput(
                    Self.attentionMasks(for: model.dummyTokens),
                    descriptor: attentionMaskDescriptor
                )
            }
        }

        var outputs = try await model.imageFunction.run(inputs: inputs)
        guard let embeddingOutput = outputs.remove(model.imageEmbedsOutputName)?.ndArray else {
            throw CLIPProviderError.invalidModel("CLIP image embedding output is missing.")
        }
        let values = Self.flattenAsFloat(embeddingOutput)
        guard !values.isEmpty else {
            throw CLIPProviderError.invalidModel("CLIP image embedding output is empty.")
        }
        try validateEmbeddingDimensions(values.count)
        return values
    }

    private func textEmbedding(
        for batch: CLIPTextBatch,
        model: LoadedCLIPModel
    ) async throws -> [Float] {
        let textEmbedsOutputName = model.textEmbedsOutputName
        let tokenInput = Self.makeTokenInput(
            batch.tokenIDs,
            descriptor: model.inputIDsDescriptor
        )
        var inputs = [model.inputIDsInputName: tokenInput]
        if let attentionMaskDescriptor = model.attentionMaskDescriptor,
           let attentionMaskInputName = model.attentionMaskInputName {
            inputs[attentionMaskInputName] = Self.makeAttentionMaskInput(
                batch.attentionMask,
                descriptor: attentionMaskDescriptor
            )
        }
        if model.textFunctionRequiresImageInput {
            inputs[model.imageInputName] = try Self.makeZeroImageInput(
                descriptor: model.imageDescriptor
            )
        }

        try Task.checkCancellation()
        var outputs = try await model.textFunction.run(inputs: inputs)
        try Task.checkCancellation()
        guard let embeddingOutput = outputs.remove(textEmbedsOutputName)?.ndArray else {
            throw CLIPTextInferenceError.missingTextEmbedsOutput
        }
        let values = try Self.validatedTextEmbeddingValues(
            embeddingOutput,
            expectedBatchSize: batch.tokenIDs.count
        )
        try validateEmbeddingDimensions(values.count)
        return values
    }

    private func validateEmbeddingDimensions(_ dimensions: Int) throws {
        guard let expected = runtimeConfiguration.embeddingDimensions else {
            return
        }
        guard dimensions == expected else {
            throw CLIPProviderError.invalidModel(
                "CLIP embedding dimension \(dimensions) does not match "
                    + "metadata.json (\(expected))."
            )
        }
    }

    private func loadModel() async throws -> LoadedCLIPModel {
        if let loadedModel { return loadedModel }

        let metadataURL = modelBundleURL.appendingPathComponent("metadata.json")
        let metadata = try JSONDecoder().decode(
            ModelBundleMetadata.self,
            from: Data(contentsOf: metadataURL)
        )
        guard let assetName = metadata.assets["main"] else {
            throw CLIPProviderError.invalidModel("metadata.json does not define assets.main.")
        }
        let modelURL = modelBundleURL.appendingPathComponent(assetName)
        let tokenizerFolder = modelBundleURL.appendingPathComponent(
            "tokenizer",
            isDirectory: true
        )
        let tokenizer: CoreAITextTokenizer
        switch runtimeConfiguration.tokenizer.type {
        case "clip-bpe":
            tokenizer = .clip(try CoreAIClipTokenizer(folder: tokenizerFolder))
        case "huggingface-tokenizer-json":
            tokenizer = .huggingFace(
                try await AutoTokenizer.from(modelFolder: tokenizerFolder)
            )
        default:
            throw CLIPProviderError.invalidModel(
                "Unsupported tokenizer type: \(runtimeConfiguration.tokenizer.type)."
            )
        }

        let model = try await AIModel(
            contentsOf: modelURL,
            options: Self.specializationOptions()
        )
        let imageFunctionName = runtimeConfiguration.imageFunctionName
        let textFunctionName = runtimeConfiguration.textFunctionName
        guard let imageFunctionDescriptor = model.functionDescriptor(
            for: imageFunctionName
        ) else {
            throw CLIPProviderError.invalidModel(
                "Cannot find \(imageFunctionName) in CLIP model."
            )
        }
        guard let textFunctionDescriptor = model.functionDescriptor(
            for: textFunctionName
        ) else {
            throw CLIPProviderError.invalidModel(
                "Cannot find \(textFunctionName) in CLIP model."
            )
        }
        guard let imageFunction = try model.loadFunction(
            named: imageFunctionName
        ) else {
            throw CLIPProviderError.invalidModel(
                "Cannot load \(imageFunctionName) from CLIP model."
            )
        }
        guard let textFunction = try model.loadFunction(
            named: textFunctionName
        ) else {
            throw CLIPProviderError.invalidModel(
                "Cannot load \(textFunctionName) from CLIP model."
            )
        }

        let imageInputName = try Self.requiredName(
            "pixel_values",
            kind: "input",
            names: imageFunctionDescriptor.inputNames
        )
        let inputIDsInputName = try Self.requiredName(
            "input_ids",
            kind: "input",
            names: textFunctionDescriptor.inputNames
        )
        let attentionMaskInputName = textFunctionDescriptor.inputNames
            .contains("attention_mask") ? "attention_mask" : nil
        let imageEmbedsOutputName = try Self.requiredName(
            "image_embeds",
            kind: "output",
            names: imageFunctionDescriptor.outputNames
        )
        let textEmbedsOutputName = try Self.requiredName(
            "text_embeds",
            kind: "output",
            names: textFunctionDescriptor.outputNames
        )

        guard case let .ndArray(imageDescriptor) =
            imageFunctionDescriptor.inputDescriptor(of: imageInputName),
            case let .ndArray(inputIDsDescriptor) =
            textFunctionDescriptor.inputDescriptor(of: inputIDsInputName)
        else {
            throw CLIPProviderError.invalidModel("CLIP inputs are not NDArrays.")
        }
        let attentionMaskDescriptor: NDArrayDescriptor? = if let attentionMaskInputName {
            if case let .ndArray(descriptor) =
                textFunctionDescriptor.inputDescriptor(of: attentionMaskInputName) {
                descriptor
            } else {
                nil
            }
        } else {
            nil
        }
        guard imageDescriptor.shape.count == 4,
              inputIDsDescriptor.shape.count == 2
        else {
            throw CLIPProviderError.invalidModel(
                "Unexpected CLIP input shapes: image=\(imageDescriptor.shape), input_ids=\(inputIDsDescriptor.shape)."
            )
        }
        guard inputIDsDescriptor.shape[0] > 0,
              inputIDsDescriptor.shape[1] > 1,
              inputIDsDescriptor.scalarType == .int32
        else {
            throw CLIPProviderError.invalidModel(
                "CLIP token input must be a non-empty Int32 [batch, context] array."
            )
        }
        if let attentionMaskDescriptor {
            guard attentionMaskDescriptor.shape == inputIDsDescriptor.shape,
                  attentionMaskDescriptor.scalarType == .int32
            else {
                throw CLIPProviderError.invalidModel(
                    "CLIP attention-mask input must match the Int32 token input."
                )
            }
        }
        guard imageDescriptor.shape[2] == runtimeConfiguration.preprocessing.height,
              imageDescriptor.shape[3] == runtimeConfiguration.preprocessing.width,
              inputIDsDescriptor.shape[1] == runtimeConfiguration.tokenizer.contextLength
        else {
            throw CLIPProviderError.invalidModel(
                "CLIP model inputs do not match metadata.json."
            )
        }

        let textBatchSize = inputIDsDescriptor.shape[0]
        let sequenceLength = inputIDsDescriptor.shape[1]
        let emptyTokens = tokenizer.encode(
            "a photo",
            contextLength: sequenceLength,
            paddingTokenID: runtimeConfiguration.tokenizer.paddingTokenID
                ?? CoreAIClipTokenizer.eotTokenId
        )
        let dummyTokens = Array(
            repeating: emptyTokens,
            count: textBatchSize
        )
        let loaded = LoadedCLIPModel(
            imageFunction: imageFunction,
            textFunction: textFunction,
            imageInputName: imageInputName,
            inputIDsInputName: inputIDsInputName,
            attentionMaskInputName: attentionMaskInputName,
            imageEmbedsOutputName: imageEmbedsOutputName,
            textEmbedsOutputName: textEmbedsOutputName,
            imageDescriptor: imageDescriptor,
            inputIDsDescriptor: inputIDsDescriptor,
            attentionMaskDescriptor: attentionMaskDescriptor,
            tokenizer: tokenizer,
            dummyTokens: dummyTokens,
            imageFunctionRequiresTextInputs: imageFunctionDescriptor.inputNames
                .contains(inputIDsInputName),
            textFunctionRequiresImageInput: textFunctionDescriptor.inputNames
                .contains(imageInputName)
        )
        loadedModel = loaded
        return loaded
    }

    private nonisolated static func specializationOptions() -> SpecializationOptions {
        var options = SpecializationOptions(preferredComputeUnitKind: .gpu)
        options.expectFrequentReshapes = false
        return options
    }

    private nonisolated static func requiredName(
        _ preferredName: String,
        kind: String,
        names: [String]
    ) throws -> String {
        guard names.contains(preferredName) else {
            throw CLIPProviderError.invalidModel(
                "CLIP \(kind) \(preferredName) is missing. Available names: \(names)."
            )
        }
        return preferredName
    }

    private nonisolated static func makeImageInput(
        _ image: CGImage,
        descriptor: NDArrayDescriptor,
        preprocessing: ModelImagePreprocessingMetadata
    ) throws -> NDArray {
        let shape = descriptor.shape
        let batchSize = shape[0]
        let channels = shape[1]
        let height = shape[2]
        let width = shape[3]
        guard batchSize == 1, channels == 3 else {
            throw CLIPProviderError.invalidModel(
                "Expected CLIP image input shape [1, 3, H, W], got \(shape)."
            )
        }
        guard width == preprocessing.width, height == preprocessing.height else {
            throw CLIPProviderError.invalidModel(
                "CLIP image input shape does not match preprocessing metadata."
            )
        }
        let pixels = try preprocessCLIPImage(
            image,
            preprocessing: preprocessing
        )
        var array = NDArray(descriptor: descriptor)
        if descriptor.scalarType == .float16 {
            #if !((os(macOS) || targetEnvironment(macCatalyst)) && arch(x86_64))
                fillNDArray(&array, as: Float16.self, with: pixels.map(Float16.init))
            #else
                throw CLIPProviderError.invalidModel("Float16 CLIP input is not supported on Intel macOS.")
            #endif
        } else {
            fillNDArray(&array, as: Float.self, with: pixels)
        }
        return array
    }

    private nonisolated static func makeZeroImageInput(
        descriptor: NDArrayDescriptor
    ) throws -> NDArray {
        let shape = descriptor.shape
        guard shape.count == 4, shape[0] == 1, shape[1] == 3 else {
            throw CLIPTextInferenceError.invalidImageInputShape(shape)
        }
        let count = shape.reduce(1, *)
        var array = NDArray(descriptor: descriptor)
        if descriptor.scalarType == .float16 {
            #if !((os(macOS) || targetEnvironment(macCatalyst)) && arch(x86_64))
                fillNDArray(&array, as: Float16.self, count: count) { _ in 0 }
            #else
                throw CLIPTextInferenceError.unsupportedInputScalarType
            #endif
        } else if descriptor.scalarType == .float32 {
            fillNDArray(&array, as: Float.self, count: count) { _ in 0 }
        } else {
            throw CLIPTextInferenceError.unsupportedInputScalarType
        }
        return array
    }

    private nonisolated static func makeTokenInput(
        _ tokens: [[Int32]],
        descriptor: NDArrayDescriptor
    ) -> NDArray {
        let batchSize = descriptor.shape[0]
        let sequenceLength = descriptor.shape[1]
        var array = NDArray(descriptor: descriptor)
        fillNDArray(&array, as: Int32.self, count: batchSize * sequenceLength) { index in
            let row = index / sequenceLength
            let column = index % sequenceLength
            guard row < tokens.count, column < tokens[row].count else {
                return CoreAIClipTokenizer.eotTokenId
            }
            return tokens[row][column]
        }
        return array
    }

    private nonisolated static func makeAttentionMaskInput(
        _ masks: [[Int32]],
        descriptor: NDArrayDescriptor
    ) -> NDArray {
        let batchSize = descriptor.shape[0]
        let sequenceLength = descriptor.shape[1]
        var array = NDArray(descriptor: descriptor)
        fillNDArray(
            &array,
            as: Int32.self,
            count: batchSize * sequenceLength
        ) { index in
            let row = index / sequenceLength
            let column = index % sequenceLength
            guard row < masks.count, column < masks[row].count else { return 0 }
            return masks[row][column]
        }
        return array
    }

    static func makeTextBatch(
        queryTokens: [Int32],
        fillerTokens: [Int32],
        batchSize: Int,
        sequenceLength: Int,
        paddingTokenID: Int32 = CoreAIClipTokenizer.eotTokenId,
        terminalTokenID: Int32 = CoreAIClipTokenizer.eotTokenId
    ) throws -> CLIPTextBatch {
        guard batchSize > 0, sequenceLength > 1 else {
            throw CLIPTextInferenceError.invalidTokenInputShape(
                [batchSize, sequenceLength]
            )
        }
        let query = normalizedTokenRow(
            queryTokens,
            sequenceLength: sequenceLength,
            paddingTokenID: paddingTokenID,
            terminalTokenID: terminalTokenID
        )
        let filler = normalizedTokenRow(
            fillerTokens,
            sequenceLength: sequenceLength,
            paddingTokenID: paddingTokenID,
            terminalTokenID: terminalTokenID
        )
        let rows = [query] + Array(repeating: filler, count: batchSize - 1)
        return CLIPTextBatch(
            tokenIDs: rows,
            attentionMask: attentionMasks(
                for: rows,
                terminalTokenID: terminalTokenID
            )
        )
    }

    private nonisolated static func normalizedTokenRow(
        _ tokens: [Int32],
        sequenceLength: Int,
        paddingTokenID: Int32,
        terminalTokenID: Int32
    ) -> [Int32] {
        if tokens.count >= sequenceLength {
            var result = Array(tokens.prefix(sequenceLength))
            if !result.dropFirst().contains(terminalTokenID) {
                result[sequenceLength - 1] = terminalTokenID
            }
            return result
        }
        return tokens + Array(
            repeating: paddingTokenID,
            count: sequenceLength - tokens.count
        )
    }

    static func applyingPaddingToken(
        to tokens: [Int32],
        paddingTokenID: Int32
    ) -> [Int32] {
        guard tokens.count > 1,
              paddingTokenID != CoreAIClipTokenizer.eotTokenId,
              let terminalIndex = tokens.dropFirst()
                  .firstIndex(of: CoreAIClipTokenizer.eotTokenId),
              terminalIndex < tokens.index(before: tokens.endIndex)
        else {
            return tokens
        }
        var result = tokens
        for index in result.index(after: terminalIndex) ..< result.endIndex {
            result[index] = paddingTokenID
        }
        return result
    }

    static func attentionMasks(
        for tokenRows: [[Int32]],
        terminalTokenID: Int32 = CoreAIClipTokenizer.eotTokenId
    ) -> [[Int32]] {
        tokenRows.map { row in
            let terminalIndex = row.dropFirst().firstIndex(of: terminalTokenID)
                ?? (row.indices.last ?? 0)
            return row.indices.map { $0 <= terminalIndex ? 1 : 0 }
        }
    }

    nonisolated static func preprocessCLIPImage(
        _ image: CGImage,
        preprocessing: ModelImagePreprocessingMetadata
    ) throws -> [Float] {
        let width = preprocessing.width
        let height = preprocessing.height
        let bytesPerPixel = 4
        let usesCenterCrop = preprocessing.resize == "shortest-side"
            && preprocessing.crop == "center"
        if usesCenterCrop {
            let rgba = try pillowBicubicCenterCrop(
                image,
                width: width,
                height: height
            )
            return normalizedCHW(
                rgba: rgba,
                width: width,
                height: height,
                mean: preprocessing.mean,
                standardDeviation: preprocessing.standardDeviation
            )
        }

        let sampledWidth: Int
        let sampledHeight: Int
        sampledWidth = width
        sampledHeight = height
        let bytesPerRow = sampledWidth * bytesPerPixel
        var rgba = [UInt8](
            repeating: 0,
            count: sampledHeight * bytesPerRow
        )
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: &rgba,
                  width: sampledWidth,
                  height: sampledHeight,
                  bitsPerComponent: 8,
                  bytesPerRow: bytesPerRow,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { throw CLIPProviderError.imagePreprocessingFailed }

        context.interpolationQuality = .medium
        context.draw(
            image,
            in: CGRect(
                x: 0,
                y: 0,
                width: sampledWidth,
                height: sampledHeight
            )
        )

        return normalizedCHW(
            rgba: rgba,
            width: width,
            height: height,
            mean: preprocessing.mean,
            standardDeviation: preprocessing.standardDeviation
        )
    }

    private nonisolated static func normalizedCHW(
        rgba: [UInt8],
        width: Int,
        height: Int,
        mean: [Float],
        standardDeviation: [Float]
    ) -> [Float] {
        let count = width * height
        var chw = [Float](repeating: 0, count: 3 * count)
        for pixel in 0 ..< count {
            let offset = pixel * 4
            let red = Float(rgba[offset]) / 255
            let green = Float(rgba[offset + 1]) / 255
            let blue = Float(rgba[offset + 2]) / 255
            chw[pixel] = (red - mean[0]) / standardDeviation[0]
            chw[count + pixel] = (green - mean[1]) / standardDeviation[1]
            chw[2 * count + pixel] = (blue - mean[2]) / standardDeviation[2]
        }
        return chw
    }

    /// Reproduces Pillow's `Image.resize(..., Resampling.BICUBIC)` followed by
    /// the integer center crop used by Hugging Face's slow CLIP processor.
    private nonisolated static func pillowBicubicCenterCrop(
        _ image: CGImage,
        width: Int,
        height: Int
    ) throws -> [UInt8] {
        let sampledWidth: Int
        let sampledHeight: Int
        if image.width > image.height {
            sampledHeight = height
            sampledWidth = Int(
                Double(height) * Double(image.width) / Double(image.height)
            )
        } else {
            sampledWidth = width
            sampledHeight = Int(
                Double(width) * Double(image.height) / Double(image.width)
            )
        }

        let cropX = centerCropOrigin(
            sampledLength: sampledWidth,
            targetLength: width
        )
        let cropY = centerCropOrigin(
            sampledLength: sampledHeight,
            targetLength: height
        )
        let source = try rgbaPixels(from: image)
        let horizontalCoefficients = pillowBicubicCoefficients(
            inputLength: image.width,
            outputLength: sampledWidth,
            outputRange: cropX ..< (cropX + width)
        )
        let verticalCoefficients = pillowBicubicCoefficients(
            inputLength: image.height,
            outputLength: sampledHeight,
            outputRange: cropY ..< (cropY + height)
        )

        var horizontal = [UInt8](
            repeating: 0,
            count: image.height * width * 3
        )
        for sourceY in 0 ..< image.height {
            for targetX in 0 ..< width {
                let coefficients = horizontalCoefficients[targetX]
                for channel in 0 ..< 3 {
                    var value = Double.zero
                    for (offset, weight) in coefficients.weights.enumerated() {
                        let sourceX = coefficients.start + offset
                        value += Double(
                            source[(sourceY * image.width + sourceX) * 4 + channel]
                        ) * weight
                    }
                    horizontal[(sourceY * width + targetX) * 3 + channel] = byte(
                        from: value
                    )
                }
            }
        }

        var output = [UInt8](repeating: 255, count: width * height * 4)
        for targetY in 0 ..< height {
            let coefficients = verticalCoefficients[targetY]
            for targetX in 0 ..< width {
                for channel in 0 ..< 3 {
                    var value = Double.zero
                    for (offset, weight) in coefficients.weights.enumerated() {
                        let sourceY = coefficients.start + offset
                        value += Double(
                            horizontal[(sourceY * width + targetX) * 3 + channel]
                        ) * weight
                    }
                    output[(targetY * width + targetX) * 4 + channel] = byte(
                        from: value
                    )
                }
            }
        }
        return output
    }

    private nonisolated static func rgbaPixels(
        from image: CGImage
    ) throws -> [UInt8] {
        let bytesPerRow = image.width * 4
        var rgba = [UInt8](
            repeating: 0,
            count: image.height * bytesPerRow
        )
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: &rgba,
                  width: image.width,
                  height: image.height,
                  bitsPerComponent: 8,
                  bytesPerRow: bytesPerRow,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { throw CLIPProviderError.imagePreprocessingFailed }
        context.interpolationQuality = .none
        context.draw(
            image,
            in: CGRect(x: 0, y: 0, width: image.width, height: image.height)
        )
        return rgba
    }

    private struct PillowBicubicCoefficients: Sendable {
        let start: Int
        let weights: [Double]
    }

    private nonisolated static func pillowBicubicCoefficients(
        inputLength: Int,
        outputLength: Int,
        outputRange: Range<Int>
    ) -> [PillowBicubicCoefficients] {
        let scale = Double(inputLength) / Double(outputLength)
        let filterScale = max(scale, 1)
        let support = 2 * filterScale
        return outputRange.map { outputIndex in
            let center = (Double(outputIndex) + 0.5) * scale
            let start = max(0, Int(center - support + 0.5))
            let end = min(inputLength, Int(center + support + 0.5))
            var weights = (start ..< end).map { inputIndex in
                pillowBicubicKernel(
                    (Double(inputIndex) + 0.5 - center) / filterScale
                )
            }
            let sum = weights.reduce(0, +)
            if sum != 0 {
                for index in weights.indices {
                    weights[index] /= sum
                }
            }
            return PillowBicubicCoefficients(start: start, weights: weights)
        }
    }

    private nonisolated static func pillowBicubicKernel(_ value: Double) -> Double {
        let x = abs(value)
        if x < 1 {
            return ((1.5 * x - 2.5) * x * x) + 1
        }
        if x < 2 {
            return (((-0.5 * x + 2.5) * x - 4) * x) + 2
        }
        return 0
    }

    private nonisolated static func byte(from value: Double) -> UInt8 {
        UInt8(clamping: Int(value.rounded()))
    }

    /// Matches Hugging Face's integer center-crop origin. When the excess is
    /// odd, integer division deliberately selects the lower/left pixel rather
    /// than rounding the half-pixel offset to the nearest even integer.
    nonisolated static func centerCropOrigin(
        sampledLength: Int,
        targetLength: Int
    ) -> Int {
        max(0, (sampledLength - targetLength) / 2)
    }

    private nonisolated static func fillNDArray<T: BitwiseCopyable>(
        _ array: inout NDArray,
        as _: T.Type,
        with elements: some Collection<T>
    ) {
        var view = array.mutableView(as: T.self)
        view.copyElements(fromContentsOf: elements)
    }

    private nonisolated static func fillNDArray<T: BitwiseCopyable>(
        _ array: inout NDArray,
        as _: T.Type,
        count: Int,
        using generator: (Int) -> T
    ) {
        let view = array.mutableView(as: T.self)
        view.withUnsafeMutablePointer { pointer, _, _ in
            for index in 0 ..< count { pointer[index] = generator(index) }
        }
    }

    private nonisolated static func flattenAsFloat(_ array: NDArray) -> [Float] {
        switch array.scalarType {
        #if !((os(macOS) || targetEnvironment(macCatalyst)) && arch(x86_64))
        case .float16:
            flattenNDArray(array, as: Float16.self)
        #endif
        case .float32:
            flattenNDArray(array, as: Float.self)
        default:
            []
        }
    }

    static func validatedTextEmbeddingValues(
        _ array: NDArray,
        expectedBatchSize: Int
    ) throws -> [Float] {
        let shape = array.shape
        guard shape.count == 2,
              shape[0] == expectedBatchSize,
              shape[1] > 0
        else {
            throw CLIPTextInferenceError.unexpectedOutputShape(
                expectedBatchSize: expectedBatchSize,
                actual: shape
            )
        }
        let values: [Float]
        switch array.scalarType {
        #if !((os(macOS) || targetEnvironment(macCatalyst)) && arch(x86_64))
        case .float16:
            values = flattenNDArray(array, as: Float16.self)
        #endif
        case .float32:
            values = flattenNDArray(array, as: Float.self)
        default:
            throw CLIPTextInferenceError.unsupportedOutputScalarType
        }
        let expectedCount = shape[0] * shape[1]
        guard values.count == expectedCount else {
            throw CLIPTextInferenceError.inconsistentOutputElementCount(
                expected: expectedCount,
                actual: values.count
            )
        }
        return Array(values.prefix(shape[1]))
    }

    private nonisolated static func flattenNDArray<T: BinaryFloatingPoint & BitwiseCopyable>(
        _ array: NDArray,
        as _: T.Type
    ) -> [Float] {
        let total = array.shape.reduce(1, *)
        var result = [Float](repeating: 0, count: total)
        array.view(as: T.self).withUnsafePointer { pointer, _, _ in
            for index in 0 ..< total { result[index] = Float(pointer[index]) }
        }
        return result
    }

    private enum CoreAITextTokenizer: Sendable {
        case clip(CoreAIClipTokenizer)
        case huggingFace(any Tokenizer)

        var eosTokenID: Int32 {
            switch self {
            case .clip:
                CoreAIClipTokenizer.eotTokenId
            case let .huggingFace(tokenizer):
                Int32(tokenizer.eosTokenId ?? 1)
            }
        }

        func encode(
            _ text: String,
            contextLength: Int,
            paddingTokenID: Int32
        ) -> [Int32] {
            switch self {
            case let .clip(tokenizer):
                return CoreAICLIPProvider.applyingPaddingToken(
                    to: tokenizer.encode(text, contextLength: contextLength),
                    paddingTokenID: paddingTokenID
                )
            case let .huggingFace(tokenizer):
                var tokens = tokenizer.encode(text: text.lowercased()).map(Int32.init)
                if tokens.count >= contextLength {
                    tokens = Array(tokens.prefix(contextLength))
                    tokens[contextLength - 1] = eosTokenID
                    return tokens
                }
                tokens.append(contentsOf: repeatElement(
                    paddingTokenID,
                    count: contextLength - tokens.count
                ))
                return tokens
            }
        }
    }

    private struct LoadedCLIPModel {
        let imageFunction: InferenceFunction
        let textFunction: InferenceFunction
        let imageInputName: String
        let inputIDsInputName: String
        let attentionMaskInputName: String?
        let imageEmbedsOutputName: String
        let textEmbedsOutputName: String
        let imageDescriptor: NDArrayDescriptor
        let inputIDsDescriptor: NDArrayDescriptor
        let attentionMaskDescriptor: NDArrayDescriptor?
        let tokenizer: CoreAITextTokenizer
        let dummyTokens: [[Int32]]
        let imageFunctionRequiresTextInputs: Bool
        let textFunctionRequiresImageInput: Bool
    }
}

struct CLIPTextBatch: Equatable, Sendable {
    let tokenIDs: [[Int32]]
    let attentionMask: [[Int32]]
}

public enum CLIPProviderError: Error, CustomStringConvertible, Sendable {
    case invalidModelBundle(ModelBundleStatus)
    case invalidModel(String)
    case imagePreprocessingFailed

    public var description: String {
        switch self {
        case let .invalidModelBundle(status): "Invalid CLIP model bundle: \(status)"
        case let .invalidModel(message): message
        case .imagePreprocessingFailed: "CLIP image preprocessing failed."
        }
    }
}

public enum CLIPSimilarityArtifactError: Error, Equatable, Sendable {
    case invalidPayload(String)
}

public enum CLIPTextInferenceError: Error, Equatable, Sendable {
    case invalidTokenInputShape([Int])
    case invalidImageInputShape([Int])
    case unsupportedInputScalarType
    case missingTextEmbedsOutput
    case unexpectedOutputShape(expectedBatchSize: Int, actual: [Int])
    case unsupportedOutputScalarType
    case inconsistentOutputElementCount(expected: Int, actual: Int)
    case invalidEmbedding(TextEmbeddingValidationError)
}

public extension ModelBundleDescriptor {
    static let clip = ModelBundleDescriptor(
        family: ModelResourceDescriptor.clip.bundleDescriptor.family,
        fallbackName: ModelResourceDescriptor.clip.bundleDescriptor.fallbackName,
        assetKey: ModelResourceDescriptor.clip.bundleDescriptor.assetKey,
        requiredRelativePaths: ModelResourceDescriptor.clip.bundleDescriptor.requiredRelativePaths,
        acceptedAssetExtensions: ModelResourceDescriptor.clip.bundleDescriptor.acceptedAssetExtensions
    )
}
