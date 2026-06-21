import Foundation

struct BrowserExifInfo: Equatable {
    let camera: String?
    let lens: String?
    let exposure: String?
    let aperture: String?
    let focalLength: String?
    let iso: String?
    let capturedAt: String?
    let dimensions: String?
    let focusPoint: BrowserFocusPoint?

    nonisolated var rows: [(String, String)] {
        [
            ("Camera", camera),
            ("Lens", lens),
            ("Exposure", exposure),
            ("Aperture", aperture),
            ("Focal Length", focalLength),
            ("ISO", iso),
            ("Captured", capturedAt),
            ("Dimensions", dimensions)
        ].compactMap { label, value in
            guard let value, !value.isEmpty else { return nil }
            return (label, value)
        }
    }

    nonisolated var isEmpty: Bool {
        rows.isEmpty
    }
}
