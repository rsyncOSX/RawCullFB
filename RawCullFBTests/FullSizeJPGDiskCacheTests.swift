import CoreGraphics
import Foundation
import ImageIO
@testable import RawCullFB
import Testing
import UniformTypeIdentifiers

@Suite("Full-size JPEG disk cache")
struct FullSizeJPGDiskCacheTests {
    @Test
    func `fallback JPEG is explicitly tagged upright`() throws {
        let image = try makeTestImage(width: 40, height: 20)
        let data = try #require(FullSizeJPGDiskCache.jpegData(from: image))
        let properties = try jpegProperties(from: data)

        #expect((properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue == 1)
    }

    @Test
    func `embedded JPEG cache applies source orientation`() async throws {
        let root = try makeTestRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let image = try makeTestImage(width: 40, height: 20)
        let sourceData = try makeJPEGData(from: image, orientation: 6)
        let embeddedData = try makeJPEGData(from: image)
        let sourceURL = root.appendingPathComponent("oriented.arw")
        try sourceData.write(to: sourceURL)

        let cache = FullSizeJPGDiskCache(
            cacheDirectory: root.appendingPathComponent("cache", isDirectory: true),
        )
        await cache.save(embeddedData, for: sourceURL)

        let loaded = await cache.load(for: sourceURL)

        #expect(loaded?.width == 20)
        #expect(loaded?.height == 40)
    }

    @Test
    func `source replacement invalidates cached preview`() async throws {
        let root = try makeTestRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let image = try makeTestImage(width: 40, height: 20)
        let sourceData = try makeJPEGData(from: image, orientation: 1)
        let cachedData = try #require(FullSizeJPGDiskCache.jpegData(from: image))
        let sourceURL = root.appendingPathComponent("replace.arw")
        try sourceData.write(to: sourceURL)

        let cache = FullSizeJPGDiskCache(
            cacheDirectory: root.appendingPathComponent("cache", isDirectory: true),
        )
        await cache.save(cachedData, for: sourceURL)
        #expect(await cache.load(for: sourceURL) != nil)

        try (sourceData + Data([0])).write(to: sourceURL, options: .atomic)

        #expect(await cache.load(for: sourceURL) == nil)
    }

    private func makeTestRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RawCullFBFullSizeCache-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeTestImage(width: Int, height: Int) throws -> CGImage {
        let context = try #require(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ))
        context.setFillColor(CGColor(red: 0.8, green: 0.2, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(context.makeImage())
    }

    private func makeJPEGData(from image: CGImage, orientation: Int? = nil) throws -> Data {
        let mutableData = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(
            mutableData,
            UTType.jpeg.identifier as CFString,
            1,
            nil,
        ))
        let properties: [CFString: Any] = if let orientation {
            [kCGImagePropertyOrientation: orientation]
        } else {
            [:]
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        try #require(CGImageDestinationFinalize(destination))
        return mutableData as Data
    }

    private func jpegProperties(from data: Data) throws -> [CFString: Any] {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        return try #require(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
        )
    }
}
