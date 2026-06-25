import Foundation

enum SupportedFileType: String, CaseIterable {
    case arw
    case nef
    case jpeg, jpg

    nonisolated static let jpegExtensions: Set<String> = [
        SupportedFileType.jpeg.rawValue,
        SupportedFileType.jpg.rawValue
    ]

    nonisolated static func isJPEG(_ url: URL) -> Bool {
        jpegExtensions.contains(url.pathExtension.lowercased())
    }
}
