@testable import CoreAICLIPBackend
import CoreGraphics
import Foundation
import ImageIO
import Testing

@Suite("SigLIP 2 CoreAI integration")
struct SigLIP2CoreAIIntegrationTests {
    @Test("CoreAI image and text encoders match PyTorch references")
    func coreAIParity() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let bundlePath = environment["SIGLIP2_COREAI_BUNDLE"],
              let referencePath = environment["SIGLIP2_REFERENCE"]
        else {
            return
        }

        let referenceURL = URL(fileURLWithPath: referencePath)
        let fixture = try JSONDecoder().decode(
            SigLIP2Reference.self,
            from: Data(contentsOf: referenceURL)
        )
        let provider = try CoreAICLIPProvider(
            modelBundleURL: URL(fileURLWithPath: bundlePath, isDirectory: true)
        )

        #expect(provider.semanticBackend == "siglip2")
        #expect(provider.runtimeConfiguration.embeddingDimensions == 768)

        for item in fixture.images {
            let imageURL = URL(
                fileURLWithPath: item.path,
                relativeTo: referenceURL.deletingLastPathComponent()
            ).standardizedFileURL
            let image = try loadImage(at: imageURL)
            let actual = try await provider.embedding(for: image).values
            // PIL and Core Graphics use slightly different bilinear kernels;
            // keep this threshold focused on end-to-end semantic parity.
            #expect(cosine(actual, item.embedding) > 0.99)
        }

        for item in fixture.texts {
            let actual = try await provider.embedding(for: item.text).values
            #expect(cosine(actual, item.embedding) > 0.995)
        }
    }

    private func loadImage(at url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw SigLIP2IntegrationError.cannotDecodeImage(url.path)
        }
        return image
    }

    private func cosine(_ left: [Float], _ right: [Float]) -> Float {
        guard left.count == right.count else { return -.infinity }
        var dot: Float = 0
        var leftSquared: Float = 0
        var rightSquared: Float = 0
        for (leftValue, rightValue) in zip(left, right) {
            dot += leftValue * rightValue
            leftSquared += leftValue * leftValue
            rightSquared += rightValue * rightValue
        }
        return dot / sqrt(leftSquared * rightSquared)
    }
}

private struct SigLIP2Reference: Decodable {
    struct ImageItem: Decodable {
        let path: String
        let embedding: [Float]
    }

    struct TextItem: Decodable {
        let text: String
        let embedding: [Float]
    }

    let images: [ImageItem]
    let texts: [TextItem]
}

private enum SigLIP2IntegrationError: Error {
    case cannotDecodeImage(String)
}
