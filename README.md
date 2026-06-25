# RawCullFB

RawCullFB is a small macOS SwiftUI file browser for quickly reviewing photo folders. It scans a selected folder and opens images in a zoomable preview. When a folder contains JPG/JPEG files, it shows only those files and loads them directly without transforming or resizing them. Otherwise, it shows supported RAW files and uses embedded or sidecar JPEG previews where available.

## Requirements

- macOS Tahoe or later
- **Apple Silicon** (M-series) only

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
- `RawCullFBicon.icon/` - Icon Composer app icon bundle used by `ASSETCATALOG_COMPILER_APPICON_NAME`.
- `Assets.xcassets/` - Shared asset catalog; the app icon is now managed by `RawCullFBicon.icon`.
- `Makefile` - Debug and release build automation.
- `exportOptions.plist` - Xcode archive export settings.
