@testable import CoreAICLIPBackend
import CoreAI
import CoreAIImageSegmenter
import CoreGraphics
import Foundation
import PhotoAIContracts
import Testing

@Suite("CLIP text capability")
struct CLIPTextCapabilityTests {
    @Test("Tokenizer fixtures cover empty, punctuation, Unicode, and truncation")
    func tokenizerFixtures() throws {
        let tokenizer = try fixtureTokenizer()

        #expect(tokenizer.encode("", contextLength: 6) == [
            CLIPTokenizer.sotTokenId,
            CLIPTokenizer.eotTokenId,
            CLIPTokenizer.eotTokenId,
            CLIPTokenizer.eotTokenId,
            CLIPTokenizer.eotTokenId,
            CLIPTokenizer.eotTokenId,
        ])
        #expect(tokenizer.encode("Hi!", contextLength: 6) == [
            CLIPTokenizer.sotTokenId,
            10,
            11,
            12,
            CLIPTokenizer.eotTokenId,
            CLIPTokenizer.eotTokenId,
        ])
        #expect(tokenizer.encode("É", contextLength: 4) == [
            CLIPTokenizer.sotTokenId,
            13,
            14,
            CLIPTokenizer.eotTokenId,
        ])
        #expect(tokenizer.encode("cat", contextLength: 4) == [
            CLIPTokenizer.sotTokenId,
            20,
            21,
            CLIPTokenizer.eotTokenId,
        ])
        #expect(tokenizer.encode("hi", contextLength: 4) == [
            CLIPTokenizer.sotTokenId,
            10,
            11,
            CLIPTokenizer.eotTokenId,
        ])
    }

    @Test("Static multi-row batches have deterministic padding and masks")
    func staticBatchAndAttentionMasks() throws {
        let tokenizer = try fixtureTokenizer()
        let empty = tokenizer.encode("", contextLength: 6)
        let filler = tokenizer.encode("hi", contextLength: 6)

        let first = try CoreAICLIPProvider.makeTextBatch(
            queryTokens: empty,
            fillerTokens: filler,
            batchSize: 3,
            sequenceLength: 6
        )
        let second = try CoreAICLIPProvider.makeTextBatch(
            queryTokens: empty,
            fillerTokens: filler,
            batchSize: 3,
            sequenceLength: 6
        )

        #expect(first == second)
        #expect(first.tokenIDs.count == 3)
        #expect(first.tokenIDs.allSatisfy { $0.count == 6 })
        #expect(first.attentionMask == [
            [1, 1, 0, 0, 0, 0],
            [1, 1, 1, 1, 0, 0],
            [1, 1, 1, 1, 0, 0],
        ])
    }

    @Test("Text output rows retain expected shape and scalar values")
    func textOutputValidation() throws {
        var output = NDArray(shape: [2, 3], scalarType: .float32)
        var view = output.mutableView(as: Float.self)
        view.copyElements(fromContentsOf: [
            0.6, 0, 0.8,
            0, 1, 0,
        ])

        let values = try CoreAICLIPProvider.validatedTextEmbeddingValues(
            output,
            expectedBatchSize: 2
        )
        #expect(values == [0.6, 0, 0.8])

        #expect(throws: CLIPTextInferenceError.unexpectedOutputShape(
            expectedBatchSize: 3,
            actual: [2, 3]
        )) {
            try CoreAICLIPProvider.validatedTextEmbeddingValues(
                output,
                expectedBatchSize: 3
            )
        }

        let unsupported = NDArray(shape: [2, 3], scalarType: .int32)
        #expect(throws: CLIPTextInferenceError.unsupportedOutputScalarType) {
            try CoreAICLIPProvider.validatedTextEmbeddingValues(
                unsupported,
                expectedBatchSize: 2
            )
        }
    }

    @Test("Text vectors reject malformed and unnormalized output")
    func textEmbeddingValidation() throws {
        let descriptor = TextEmbeddingDescriptor(
            backend: fixtureBackend(),
            dimensions: 2,
            tokenizerVersion: CoreAICLIPProvider.tokenizerVersion
        )

        #expect(throws: TextEmbeddingValidationError.dimensionMismatch(
            expected: 2,
            actual: 1
        )) {
            try TextEmbedding(descriptor: descriptor, values: [1])
        }
        #expect(throws: TextEmbeddingValidationError.nonFiniteValue(index: 1)) {
            try TextEmbedding(descriptor: descriptor, values: [1, .infinity])
        }
        #expect(throws: TextEmbeddingValidationError.zeroNorm) {
            try TextEmbedding(descriptor: descriptor, values: [0, 0])
        }
        #expect(throws: TextEmbeddingValidationError.notNormalized(magnitude: 2)) {
            try TextEmbedding(descriptor: descriptor, values: [2, 0])
        }
    }

    @Test("Compatible image/text scoring ranks related vectors first")
    func compatibleRetrievalFixture() throws {
        let fixture = try comparisonFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let query = try TextEmbedding(
            descriptor: fixture.textDescriptor,
            values: [0.8, 0.6]
        )
        let related = try fixture.artifact(values: [1, 0])
        let unrelated = try fixture.artifact(values: [0, 1])

        let relatedScore = try fixture.provider.similarity(
            image: related,
            text: query
        )
        let unrelatedScore = try fixture.provider.similarity(
            image: unrelated,
            text: query
        )

        #expect(relatedScore > unrelatedScore)
        #expect(abs(relatedScore - 0.8) < 0.0001)
        #expect(abs(unrelatedScore - 0.6) < 0.0001)
    }

    @Test("Comparison rejects every incompatible descriptor field")
    func incompatibleDescriptors() throws {
        let fixture = try comparisonFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let image = try fixture.artifact(values: [1, 0])

        try expectComparisonError(
            .unsupportedTextBackend(expected: "clip", actual: "vision"),
            fixture: fixture,
            image: image,
            backend: replacing(fixture.backend, backend: "vision")
        )
        try expectComparisonError(
            .incompatibleModelFingerprint,
            fixture: fixture,
            image: image,
            backend: replacing(fixture.backend, modelFingerprint: "other")
        )
        try expectComparisonError(
            .incompatibleRepresentation,
            fixture: fixture,
            image: image,
            backend: replacing(fixture.backend, representation: "other")
        )
        try expectComparisonError(
            .incompatiblePreprocessing,
            fixture: fixture,
            image: image,
            backend: replacing(fixture.backend, preprocessingVersion: "other")
        )
        try expectComparisonError(
            .incompatibleNormalization,
            fixture: fixture,
            image: image,
            backend: replacing(fixture.backend, normalizationVersion: "other")
        )
        try expectComparisonError(
            .incompatibleConfiguration,
            fixture: fixture,
            image: image,
            backend: replacing(fixture.backend, configurationVersion: "other")
        )

        let wrongDimensions = try TextEmbedding(
            descriptor: TextEmbeddingDescriptor(
                backend: fixture.backend,
                dimensions: 3,
                tokenizerVersion: CoreAICLIPProvider.tokenizerVersion
            ),
            values: [1, 0, 0]
        )
        #expect(throws: ImageTextSimilarityError.incompatibleDimensions(
            expected: 3,
            actual: 2
        )) {
            try fixture.provider.similarity(image: image, text: wrongDimensions)
        }

        let wrongTokenizer = try TextEmbedding(
            descriptor: TextEmbeddingDescriptor(
                backend: fixture.backend,
                dimensions: 2,
                tokenizerVersion: "other"
            ),
            values: [1, 0]
        )
        #expect(throws: ImageTextSimilarityError.incompatibleTokenizer) {
            try fixture.provider.similarity(image: image, text: wrongTokenizer)
        }
    }

    @Test("Comparison rejects Vision and malformed CLIP artifacts")
    func incompatibleAndMalformedArtifacts() throws {
        let fixture = try comparisonFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let text = try TextEmbedding(
            descriptor: fixture.textDescriptor,
            values: [1, 0]
        )
        let vision = SimilarityArtifact(
            descriptor: SimilarityArtifactDescriptor(
                backend: replacing(fixture.backend, backend: "vision"),
                dimensions: 2,
                sourceFingerprint: fixture.source
            ),
            payload: Data()
        )
        #expect(throws: ImageTextSimilarityError.unsupportedImageBackend(
            expected: "clip",
            actual: "vision"
        )) {
            try fixture.provider.similarity(image: vision, text: text)
        }

        let malformed = SimilarityArtifact(
            descriptor: SimilarityArtifactDescriptor(
                backend: fixture.backend,
                dimensions: 2,
                sourceFingerprint: fixture.source
            ),
            payload: Data("not-json".utf8)
        )
        #expect(throws: ImageTextSimilarityError.self) {
            try fixture.provider.similarity(image: malformed, text: text)
        }
    }

    @Test("A cancelled text request stops before model loading")
    func cancellationBeforeModelLoad() async throws {
        let fixture = try comparisonFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let task = Task {
            await Task.yield()
            return try await fixture.provider.embedding(for: "bird")
        }
        task.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }

    @Test("DataComp metadata selects 256-pixel dual-encoder runtime")
    func dataCompRuntimeConfiguration() throws {
        let preprocessing = ModelImagePreprocessingMetadata(
            version: "clip-center-256-v2",
            width: 256,
            height: 256,
            resize: "shortest-side",
            crop: "center",
            interpolation: "bicubic",
            mean: [0.48145466, 0.4578275, 0.40821073],
            standardDeviation: [0.26862954, 0.26130258, 0.27577711]
        )
        let metadata = ModelBundleMetadata(
            name: "DataComp",
            family: "clip",
            sourceModel: "mlfoundations/open_clip",
            architecture: "ViT-B-32-256",
            pretrained: "datacomp_s34b_b86k",
            metadataVersion: "0.4",
            embeddingDimensions: 512,
            assets: ["main": "datacomp.aimodel"],
            assetFingerprints: nil,
            preprocessing: preprocessing,
            tokenizer: ModelTokenizerMetadata(
                version: "clip-bpe-tokenizer-v1",
                type: "clip-bpe",
                contextLength: 77,
                paddingTokenID: 0
            ),
            functions: [
                "image": "image_encoder",
                "text": "text_encoder",
            ],
            normalizationVersion: "l2-v1",
            configurationVersion: "coreai-clip-dual-encoder-v2"
        )

        let configuration = try CLIPRuntimeConfiguration(metadata: metadata)

        #expect(configuration.architecture == "ViT-B-32-256")
        #expect(configuration.pretrained == "datacomp_s34b_b86k")
        #expect(configuration.preprocessing == preprocessing)
        #expect(configuration.embeddingDimensions == 512)
        #expect(configuration.tokenizer.paddingTokenID == 0)
        #expect(configuration.imageFunctionName == "image_encoder")
        #expect(configuration.textFunctionName == "text_encoder")
    }

    @Test("CLIP preprocessing center-crops instead of stretching")
    func centerCropPreprocessing() throws {
        let image = try #require(colorBandImage())
        let preprocessing = ModelImagePreprocessingMetadata(
            version: "test-center-crop",
            width: 2,
            height: 2,
            resize: "shortest-side",
            crop: "center",
            interpolation: "bicubic",
            mean: [0, 0, 0],
            standardDeviation: [1, 1, 1]
        )

        let values = try CoreAICLIPProvider.preprocessCLIPImage(
            image,
            preprocessing: preprocessing
        )

        #expect(values.count == 12)
        let pixelsPerChannel = 4
        let averageRed = values[0 ..< pixelsPerChannel].reduce(0, +)
            / Float(pixelsPerChannel)
        let averageGreen = values[
            pixelsPerChannel ..< (pixelsPerChannel * 2)
        ].reduce(0, +) / Float(pixelsPerChannel)
        #expect(averageRed < 0.2)
        #expect(averageGreen > 0.8)
    }

    @Test("CLIP center crop floors odd half-pixel offsets like Hugging Face")
    func centerCropUsesHuggingFaceIntegerOrigin() {
        #expect(CoreAICLIPProvider.centerCropOrigin(
            sampledLength: 339,
            targetLength: 224
        ) == 57)
        #expect(CoreAICLIPProvider.centerCropOrigin(
            sampledLength: 331,
            targetLength: 224
        ) == 53)
        #expect(CoreAICLIPProvider.centerCropOrigin(
            sampledLength: 336,
            targetLength: 224
        ) == 56)
    }

    @Test("Corrected CLIP preprocessing invalidates older cached embeddings")
    func correctedPreprocessingHasDistinctCacheVersion() {
        let centerCrop = ModelImagePreprocessingMetadata(
            version: "clip-preprocessing-v3",
            width: 224,
            height: 224,
            resize: "shortest-side",
            crop: "center",
            interpolation: "bicubic",
            mean: [0, 0, 0],
            standardDeviation: [1, 1, 1]
        )
        let stretch = ModelImagePreprocessingMetadata(
            version: "siglip-stretch-v1",
            width: 256,
            height: 256,
            resize: "stretch",
            crop: "none",
            interpolation: "bilinear",
            mean: [0.5, 0.5, 0.5],
            standardDeviation: [0.5, 0.5, 0.5]
        )

        #expect(CoreAICLIPProvider.effectivePreprocessingVersion(
            for: centerCrop
        ) == "clip-preprocessing-v3:photoaikit-pillow-bicubic-v1")
        #expect(CoreAICLIPProvider.effectivePreprocessingVersion(
            for: stretch
        ) == "siglip-stretch-v1")
    }

    @Test("CLIP bicubic resize matches Pillow reference pixels")
    func bicubicResizeMatchesPillow() throws {
        let image = try #require(patternedImage())
        let preprocessing = ModelImagePreprocessingMetadata(
            version: "test-pillow-bicubic",
            width: 4,
            height: 4,
            resize: "shortest-side",
            crop: "center",
            interpolation: "bicubic",
            mean: [0, 0, 0],
            standardDeviation: [1, 1, 1]
        )
        let values = try CoreAICLIPProvider.preprocessCLIPImage(
            image,
            preprocessing: preprocessing
        )
        let expected: [(UInt8, UInt8, UInt8)] = [
            (8, 9, 7), (50, 23, 33), (94, 39, 60), (138, 55, 87),
            (17, 62, 35), (59, 76, 61), (103, 92, 88), (147, 108, 115),
            (25, 116, 65), (67, 130, 91), (111, 146, 118), (155, 162, 145),
            (34, 169, 93), (76, 183, 119), (120, 199, 146), (164, 215, 173),
        ]
        let count = 16
        for (pixel, rgb) in expected.enumerated() {
            #expect(UInt8(clamping: Int((values[pixel] * 255).rounded())) == rgb.0)
            #expect(UInt8(clamping: Int((values[count + pixel] * 255).rounded())) == rgb.1)
            #expect(UInt8(clamping: Int((values[(2 * count) + pixel] * 255).rounded())) == rgb.2)
        }
    }

    @Test("SigLIP 2 metadata selects fixed-resolution tokenizer runtime")
    func siglip2RuntimeConfiguration() throws {
        let preprocessing = ModelImagePreprocessingMetadata(
            version: "siglip2-stretch-256-v1",
            width: 256,
            height: 256,
            resize: "stretch",
            crop: "none",
            interpolation: "bilinear",
            mean: [0.5, 0.5, 0.5],
            standardDeviation: [0.5, 0.5, 0.5]
        )
        let metadata = ModelBundleMetadata(
            name: "SigLIP 2 Base/16-256",
            family: "siglip2",
            sourceModel: "google/siglip2-base-patch16-256",
            sourceRevision: "3f9f96cb90da5dbc758b01813f2f6f1aee24c1ab",
            architecture: "SigLIP2-Base-Patch16-256",
            pretrained: "webli-siglip2",
            metadataVersion: "0.4",
            embeddingDimensions: 768,
            assets: ["main": "siglip2.aimodel"],
            assetFingerprints: nil,
            preprocessing: preprocessing,
            tokenizer: ModelTokenizerMetadata(
                version: "siglip2-tokenizer-v1",
                type: "huggingface-tokenizer-json",
                contextLength: 64,
                paddingTokenID: 0
            ),
            functions: [
                "image": "image_encoder",
                "text": "text_encoder",
            ],
            normalizationVersion: "l2-v1",
            configurationVersion: "coreai-siglip2-dual-encoder-v1"
        )

        let configuration = try CLIPRuntimeConfiguration(metadata: metadata)

        #expect(configuration.architecture == "SigLIP2-Base-Patch16-256")
        #expect(configuration.embeddingDimensions == 768)
        #expect(configuration.preprocessing == preprocessing)
        #expect(configuration.tokenizer.type == "huggingface-tokenizer-json")
        #expect(configuration.tokenizer.contextLength == 64)
        #expect(configuration.tokenizer.paddingTokenID == 0)
    }

    @Test("CLIP preprocessing preserves top-to-bottom pixel orientation")
    func preprocessingOrientation() throws {
        let image = try #require(verticalBandImage())
        let preprocessing = ModelImagePreprocessingMetadata(
            version: "test-orientation",
            width: 2,
            height: 2,
            resize: "stretch",
            crop: "none",
            interpolation: "bilinear",
            mean: [0, 0, 0],
            standardDeviation: [1, 1, 1]
        )

        let values = try CoreAICLIPProvider.preprocessCLIPImage(
            image,
            preprocessing: preprocessing
        )

        #expect(values[0] > 0.8)
        #expect(values[1] > 0.8)
        #expect(values[2] < 0.2)
        #expect(values[3] < 0.2)
    }

    @Test("Legacy bundles retain the original 224-pixel stretch contract")
    func legacyRuntimeConfiguration() throws {
        let metadata = ModelBundleMetadata(
            name: "legacy",
            family: "clip",
            assets: ["main": "legacy.aimodel"]
        )

        let configuration = try CLIPRuntimeConfiguration(metadata: metadata)

        #expect(configuration.preprocessing.width == 224)
        #expect(configuration.preprocessing.resize == "stretch")
        #expect(configuration.preprocessing.crop == "none")
        #expect(configuration.imageFunctionName == "main")
        #expect(configuration.textFunctionName == "main")
    }

    @Test("DataComp token rows use zero padding after end-of-text")
    func dataCompTokenPadding() {
        let original: [Int32] = [
            CLIPTokenizer.sotTokenId,
            42,
            CLIPTokenizer.eotTokenId,
            CLIPTokenizer.eotTokenId,
            CLIPTokenizer.eotTokenId,
        ]

        #expect(CoreAICLIPProvider.applyingPaddingToken(
            to: original,
            paddingTokenID: 0
        ) == [
            CLIPTokenizer.sotTokenId,
            42,
            CLIPTokenizer.eotTokenId,
            0,
            0,
        ])
        #expect(CoreAICLIPProvider.applyingPaddingToken(
            to: original,
            paddingTokenID: CLIPTokenizer.eotTokenId
        ) == original)
    }

    @Test("SigLIP token batches preserve EOS and mask zero padding")
    func siglipTokenBatch() throws {
        let batch = try CoreAICLIPProvider.makeTextBatch(
            queryTokens: [42, 43, 1, 0, 0],
            fillerTokens: [44, 1, 0, 0, 0],
            batchSize: 2,
            sequenceLength: 5,
            paddingTokenID: 0,
            terminalTokenID: 1
        )

        #expect(batch.tokenIDs == [
            [42, 43, 1, 0, 0],
            [44, 1, 0, 0, 0],
        ])
        #expect(batch.attentionMask == [
            [1, 1, 1, 0, 0],
            [1, 1, 0, 0, 0],
        ])
    }

    private func fixtureTokenizer() throws -> CoreAIClipTokenizer {
        try CoreAIClipTokenizer(
            vocab: [
                "h": 10,
                "i</w>": 11,
                "!</w>": 12,
                "Ã": 13,
                "©</w>": 14,
                "c": 20,
                "a": 21,
                "t</w>": 22,
            ],
            merges: []
        )
    }

    private func comparisonFixture() throws -> ComparisonFixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("tokenizer", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data("{}".utf8).write(
            to: root.appendingPathComponent("tokenizer/tokenizer.json")
        )
        try Data().write(to: root.appendingPathComponent("model.aimodel"))
        let metadata = ModelBundleMetadata(
            name: "text-test",
            family: "clip",
            assets: ["main": "model.aimodel"]
        )
        try JSONEncoder().encode(metadata).write(
            to: root.appendingPathComponent("metadata.json")
        )
        let provider = try CoreAICLIPProvider(modelBundleURL: root)
        return ComparisonFixture(root: root, provider: provider)
    }

    private func expectComparisonError(
        _ error: ImageTextSimilarityError,
        fixture: ComparisonFixture,
        image: SimilarityArtifact,
        backend: SimilarityBackendDescriptor
    ) throws {
        let text = try TextEmbedding(
            descriptor: TextEmbeddingDescriptor(
                backend: backend,
                dimensions: 2,
                tokenizerVersion: CoreAICLIPProvider.tokenizerVersion
            ),
            values: [1, 0]
        )
        #expect(throws: error) {
            try fixture.provider.similarity(image: image, text: text)
        }
    }
}

private func colorBandImage() -> CGImage? {
    let width = 4
    let height = 2
    let red: [UInt8] = [255, 0, 0, 255]
    let green: [UInt8] = [0, 255, 0, 255]
    let row = red + green + green + red
    let pixels = row + row
    guard let provider = CGDataProvider(data: Data(pixels) as CFData) else {
        return nil
    }
    return CGImage(
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(
            rawValue: CGImageAlphaInfo.last.rawValue
        ),
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    )
}

private func verticalBandImage() -> CGImage? {
    let width = 2
    let height = 2
    let red: [UInt8] = [255, 0, 0, 255]
    let blue: [UInt8] = [0, 0, 255, 255]
    let pixels = red + red + blue + blue
    guard let provider = CGDataProvider(data: Data(pixels) as CFData) else {
        return nil
    }
    return CGImage(
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(
            rawValue: CGImageAlphaInfo.last.rawValue
        ),
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    )
}

private func patternedImage() -> CGImage? {
    let width = 7
    let height = 5
    var pixels: [UInt8] = []
    pixels.reserveCapacity(width * height * 4)
    for y in 0 ..< height {
        for x in 0 ..< width {
            pixels.append(UInt8((x * 31 + y * 7) % 256))
            pixels.append(UInt8((x * 11 + y * 43) % 256))
            pixels.append(UInt8((x * 19 + y * 23) % 256))
            pixels.append(255)
        }
    }
    guard let provider = CGDataProvider(data: Data(pixels) as CFData) else {
        return nil
    }
    return CGImage(
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    )
}

private struct ComparisonFixture {
    let root: URL
    let provider: CoreAICLIPProvider

    var backend: SimilarityBackendDescriptor {
        provider.backendDescriptor
    }

    var textDescriptor: TextEmbeddingDescriptor {
        TextEmbeddingDescriptor(
            backend: backend,
            dimensions: 2,
            tokenizerVersion: CoreAICLIPProvider.tokenizerVersion
        )
    }

    var source: SourceFingerprint {
        SourceFingerprint(
            standardizedPath: "/tmp/text-test.raw",
            fileSize: 1,
            modificationDate: nil
        )
    }

    func artifact(values: [Float]) throws -> SimilarityArtifact {
        let embedding = ImageEmbedding(
            backend: backend.backend,
            modelIdentity: provider.modelIdentity,
            values: values
        )
        return SimilarityArtifact(
            descriptor: SimilarityArtifactDescriptor(
                backend: backend,
                dimensions: values.count,
                sourceFingerprint: source
            ),
            payload: try JSONEncoder().encode(embedding)
        )
    }
}

private func fixtureBackend() -> SimilarityBackendDescriptor {
    SimilarityBackendDescriptor(
        backend: "clip",
        modelFingerprint: "test-model",
        representation: "normalized-float-vector-json-v1",
        preprocessingVersion: "clip-srgb-bilinear-chw-v1",
        normalizationVersion: "l2-v1",
        configurationVersion: "test-v1"
    )
}

private func replacing(
    _ descriptor: SimilarityBackendDescriptor,
    backend: String? = nil,
    modelFingerprint: String? = nil,
    representation: String? = nil,
    preprocessingVersion: String? = nil,
    normalizationVersion: String? = nil,
    configurationVersion: String? = nil
) -> SimilarityBackendDescriptor {
    SimilarityBackendDescriptor(
        backend: backend ?? descriptor.backend,
        modelFingerprint: modelFingerprint ?? descriptor.modelFingerprint,
        representation: representation ?? descriptor.representation,
        preprocessingVersion: preprocessingVersion ?? descriptor.preprocessingVersion,
        normalizationVersion: normalizationVersion ?? descriptor.normalizationVersion,
        configurationVersion: configurationVersion ?? descriptor.configurationVersion
    )
}
