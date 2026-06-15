# RawCullFB

RawCullFB is a small macOS SwiftUI file browser for quickly reviewing raw photo folders. It scans a selected folder, shows supported raw files in a thumbnail grid, and opens a zoomable preview using the embedded or sidecar JPEG where available.

## Features

- Add local folders through the macOS folder picker.
- Browse nested folders in a sidebar.
- Generate in-memory thumbnails for supported raw formats.
- Open a zoom overlay with keyboard navigation, pan, and magnification controls.
- Display available EXIF details such as camera, lens, exposure, ISO, dimensions, and focus point.
- Prefer matching `.jpg` sidecars for full preview images when present.

## Requirements

- macOS with Xcode installed.
- SwiftUI and Swift Package Manager support through the Xcode project.
- The `RawParserKit` package dependency resolved by `RawCullFB.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.

## Development

Open the project in Xcode:

```sh
open RawCullFB.xcodeproj
```

Build from the command line:

```sh
xcodebuild -project RawCullFB.xcodeproj -scheme RawCullFB -destination 'platform=macOS' build
```

Create a local debug archive:

```sh
make debug
```

Create a signed, notarized release build and DMG:

```sh
make build
```

The release workflow expects the local signing identity, notarization keychain profile, and `../create-dmg/create-dmg` helper referenced in the `Makefile`.

## Project Layout

- `RawCullFB/` - SwiftUI app source.
- `RawCullFB.xcodeproj/` - Xcode project and Swift package resolution files.
- `Makefile` - Debug and release build automation.
- `exportOptions.plist` - Xcode archive export settings.
