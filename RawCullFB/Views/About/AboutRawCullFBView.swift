import AppKit
import SwiftUI

struct AboutRawCullFBView: View {
    private let shortcuts = [
        ShortcutRow(context: "Grid", keys: "Arrow keys / N / P", action: "Select next or previous image"),
        ShortcutRow(context: "Grid", keys: "Return", action: "Open selected image in zoom"),
        ShortcutRow(context: "Grid", keys: "Z", action: "Inspect focus point at 60% pixels"),
        ShortcutRow(context: "Zoom", keys: "N / P", action: "Show next or previous image"),
        ShortcutRow(context: "Zoom", keys: "E", action: "Show or hide EXIF data"),
        ShortcutRow(context: "Zoom", keys: "A", action: "Show or hide focus point"),
        ShortcutRow(context: "Zoom", keys: "Z", action: "Inspect focus point at 60% pixels"),
        ShortcutRow(context: "Zoom", keys: "+ / -", action: "Zoom in or out"),
        ShortcutRow(context: "Zoom", keys: "Esc", action: "Close zoom")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 3) {
                    Text("RawCullFB")
                        .font(.title2.weight(.semibold))

                    Text(versionText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Text("Fast folder-based RAW browsing with embedded JPEG preview, EXIF details, histogram, and focus point overlay.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                Text("Keystrokes")
                    .font(.headline)

                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                    ForEach(shortcuts) { shortcut in
                        GridRow {
                            Text(shortcut.context)
                                .foregroundStyle(.secondary)
                            Text(shortcut.keys)
                                .font(.system(.body, design: .monospaced).weight(.medium))
                            Text(shortcut.action)
                        }
                    }
                }
                .font(.callout)
            }
        }
        .padding(24)
        .frame(width: 470, alignment: .leading)
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        return switch (version, build) {
        case let (version?, build?):
            "Version \(version) (\(build))"

        case let (version?, nil):
            "Version \(version)"

        case let (nil, build?):
            "Build \(build)"

        default:
            "Version unavailable"
        }
    }
}
