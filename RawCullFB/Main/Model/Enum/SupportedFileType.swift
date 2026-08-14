import Foundation

enum SupportedFileType: String, CaseIterable {
    case arw
    case nef
    case jpeg, jpg
    case png
    case tif, tiff

    nonisolated static let renderedImageExtensions: Set<String> = [
        SupportedFileType.jpeg.rawValue,
        SupportedFileType.jpg.rawValue,
        SupportedFileType.png.rawValue,
        SupportedFileType.tif.rawValue,
        SupportedFileType.tiff.rawValue
    ]

    nonisolated static func isRenderedImage(_ url: URL) -> Bool {
        renderedImageExtensions.contains(url.pathExtension.lowercased())
    }
}
