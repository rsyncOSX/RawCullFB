import CoreAIImageSegmenter
import CoreGraphics
import Foundation
import PhotoAIContracts

// ImageSegmenter is immutable after construction and remains actor-confined.
// Recheck this conformance when updating the pinned coreai-models revision.
extension ImageSegmenter: @retroactive @unchecked Sendable {}

/// Actor-owned Core AI EfficientSAM runtime.
///
/// EfficientSAM accepts point prompts rather than text. PhotoAIKit uses the
/// model's empty point query, which selects a center point for a Q=1 export or
/// a regular grid for a perfect-square multi-query export. The highest-scoring
/// mask is adapted to the shared subject-segmentation contract.
public actor CoreAIEfficientSAMProvider: SubjectSegmenting {
    public nonisolated let modelIdentity: ModelIdentity

    public nonisolated static let resourceDescriptor = ModelResourceDescriptor.efficientSAM

    public nonisolated static var factory: ModelProviderFactory<CoreAIEfficientSAMProvider> {
        ModelProviderFactory(descriptor: resourceDescriptor) { url in
            try CoreAIEfficientSAMProvider(modelBundleURL: url)
        }
    }

    private let modelBundleURL: URL
    private var segmenter: ImageSegmenter?
    private nonisolated static let parameters = SegmentationParameters(
        maskThreshold: 0.5,
        maxSegments: 1
    )

    public init(modelBundleURL: URL) throws {
        let resolver = ModelBundleResolver(descriptor: Self.resourceDescriptor.bundleDescriptor)
        guard case let .valid(_, identity) = resolver.status(at: modelBundleURL) else {
            throw EfficientSAMProviderError.invalidModelBundle(resolver.status(at: modelBundleURL))
        }
        self.modelBundleURL = modelBundleURL
        self.modelIdentity = identity
    }

    public func segment(
        _ request: SubjectSegmentationRequest
    ) async throws -> SubjectSegmentationResult {
        let totalStart = CFAbsoluteTimeGetCurrent()
        guard !Task.isCancelled else { throw SubjectSegmentationError.cancelled }
        let segmenter = try await loadSegmenter()

        let response: SegmentationResponse
        do {
            response = try await segmenter.segment(
                image: request.image,
                pointQuery: PointQuery(),
                parameters: Self.parameters
            )
        } catch is CancellationError {
            throw SubjectSegmentationError.cancelled
        } catch {
            throw SubjectSegmentationError.providerFailure(Self.message(for: error))
        }
        guard !Task.isCancelled else { throw SubjectSegmentationError.cancelled }
        guard let best = response.segments.first else {
            throw SubjectSegmentationError.noMask
        }

        let mask = try Self.makeMaskImage(from: best)
        let timing = SubjectSegmentationTiming(
            totalMilliseconds: (CFAbsoluteTimeGetCurrent() - totalStart) * 1_000
        )
        let outputSize = CGSize(width: mask.width, height: mask.height)
        let diagnostics = SubjectSegmentationDiagnostics(
            modelIdentity: modelIdentity,
            prompt: request.prompt,
            confidence: best.score,
            timing: timing,
            inputSize: request.inputSize,
            outputSize: outputSize,
            resourceName: modelBundleURL.lastPathComponent,
            assetName: modelIdentity.assetName
        )
        return SubjectSegmentationResult(
            sourceID: request.sourceID,
            requestID: request.requestID,
            prompt: request.prompt,
            mask: mask,
            confidence: best.score,
            modelIdentity: modelIdentity,
            inputSize: request.inputSize,
            outputSize: outputSize,
            timing: timing,
            diagnostics: diagnostics
        )
    }

    private func loadSegmenter() async throws -> ImageSegmenter {
        if let segmenter { return segmenter }
        do {
            let loaded = try await ImageSegmenter(
                resourcesAt: modelBundleURL.path,
                parameters: Self.parameters
            )
            segmenter = loaded
            return loaded
        } catch {
            throw EfficientSAMProviderError.modelLoad(Self.message(for: error))
        }
    }

    private nonisolated static func makeMaskImage(from segment: Segment) throws -> CGImage {
        guard segment.maskWidth > 0,
              segment.maskHeight > 0,
              segment.mask.count == segment.maskWidth * segment.maskHeight
        else {
            throw SubjectSegmentationError.decodeFailure
        }

        var pixels = [UInt8](repeating: 0, count: segment.mask.count * 4)
        for (index, isForeground) in segment.mask.enumerated() where isForeground {
            let offset = index * 4
            pixels[offset] = 255
            pixels[offset + 1] = 255
            pixels[offset + 2] = 255
            pixels[offset + 3] = 255
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(
                  width: segment.maskWidth,
                  height: segment.maskHeight,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: segment.maskWidth * 4,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: true,
                  intent: .defaultIntent
              )
        else {
            throw SubjectSegmentationError.decodeFailure
        }
        return image
    }

    private nonisolated static func message(for error: Error) -> String {
        let description = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if !description.isEmpty,
           description != "The operation couldn’t be completed. (Swift.Error error 1.)" {
            return description
        }
        return String(reflecting: error)
    }
}

public enum EfficientSAMProviderError: Error, CustomStringConvertible, Sendable {
    case invalidModelBundle(ModelBundleStatus)
    case modelLoad(String)

    public var description: String {
        switch self {
        case let .invalidModelBundle(status): "Invalid EfficientSAM model bundle: \(status)"
        case let .modelLoad(message): "EfficientSAM model load failed: \(message)"
        }
    }
}

public extension ModelBundleDescriptor {
    static let efficientSAM = ModelBundleDescriptor(
        family: ModelResourceDescriptor.efficientSAM.bundleDescriptor.family,
        fallbackName: ModelResourceDescriptor.efficientSAM.bundleDescriptor.fallbackName,
        assetKey: ModelResourceDescriptor.efficientSAM.bundleDescriptor.assetKey,
        requiredRelativePaths: ModelResourceDescriptor.efficientSAM.bundleDescriptor.requiredRelativePaths,
        acceptedAssetExtensions: ModelResourceDescriptor.efficientSAM.bundleDescriptor.acceptedAssetExtensions
    )
}
