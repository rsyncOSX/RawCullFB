import AppKit

final class CachedNSImage: NSObject, @unchecked Sendable {
    let image: NSImage
    nonisolated let cost: Int

    nonisolated init(image: NSImage) {
        self.image = image
        var totalCost = 0
        for representation in image.representations {
            totalCost += representation.pixelsWide * representation.pixelsHigh * 4
        }
        if totalCost == 0 {
            totalCost = Int(image.size.width * image.size.height * 4)
        }
        self.cost = Int(Double(totalCost) * 1.1)
        super.init()
    }
}
