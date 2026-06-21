import AppKit

final class CachedCGImage: NSObject, @unchecked Sendable {
    let image: CGImage
    nonisolated let cost: Int

    nonisolated init(image: CGImage) {
        self.image = image
        self.cost = Int(Double(image.width * image.height * 4) * 1.1)
        super.init()
    }
}
