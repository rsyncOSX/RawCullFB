# RawCullFB

RawCullFB is a macOS SwiftUI photo browser with local CLIP or SigLIP 2 indexing and semantic search. It preserves the normal folder browser and zoomable preview while adding recursive semantic search over JPEG, PNG, HEIC/HEIF, TIFF, and Sony ARW files.

## Requirements

- macOS 27 or later
- **Apple Silicon** (M-series) only
- A compatible Core AI CLIP or fixed-resolution SigLIP 2 model bundle selected by the user

## Features

- Add local folders through the macOS folder picker.
- Browse nested folders in a sidebar.
- Generate in-memory thumbnails for supported RAW, JPEG, TIFF, and PNG files.
- Open a zoom overlay with keyboard navigation, pan, and magnification controls.
- Display available EXIF details such as camera, lens, exposure, ISO, dimensions, and focus point.
- Prefer matching `.jpg` sidecars for RAW full preview images when present.
- Verify user-selected CLIP bundles before enabling indexing or search.
- Recursively and incrementally index a selected folder into its hidden `.clipbench` directory.
- Search locally with natural-language descriptions and show thumbnail/path results.
- Adjust the semantic result limit in steps of ten (default 50, range 10–500).

## SigLIP 2 test bundle

The development project uses the sibling `../PhotoAIKit` checkout so the experimental SigLIP 2 runtime can be tested before publishing a PhotoAIKit release. Generate the bundle with:

```sh
cd ../PhotoAIKit
uv run Tools/export_siglip2.py \
  --source-dir ../../Models/SigLIP2-Base-Patch16-256/source \
  --output-dir ../../Models/SigLIP2-Base-Patch16-256 \
  --overwrite
```

In **RawCullFB > Settings > CLIP**, select:

```text
../../Models/SigLIP2-Base-Patch16-256/SigLIP2-Base-Patch16-256
```

The model reports as `SigLIP2-Base-Patch16-256`. Its index uses the `siglip2` backend plus the model fingerprint, so RawCullFB will not mix it with an existing OpenAI CLIP or DataComp CLIP index. Re-index the selected photo folder before comparing searches.

## CLIP workflow

1. Open **RawCullFB > Settings > CLIP** and choose a compatible model bundle.
2. Wait for the model to report a valid verification status.
3. Select the folder that should become the recursive index root.
4. Choose **Index Selected Folder** in the main toolbar. Indexing never starts automatically.
5. Enter a description in the semantic search field and press Return or Search.
6. Double-click a result to inspect its full embedded/rendered JPEG with EXIF information and histogram.

RawCullFB stores one model-specific index at `.clipbench/clip-<model-hash>.clipindex` inside the selected root. Source photographs are not modified. Model inference, embeddings, and search stay on the Mac.

### Semantic test mode

Place a UTF-8 file named `semantictest.txt` in the selected photo-folder root, with one semantic query per line. Empty lines and lines beginning with `#` are ignored. After selecting and indexing a model, choose **Run Semantic Test** in the main toolbar.

RawCullFB executes the queries sequentially using the current result limit and displays each completed result set. It atomically updates `<model-name>-semantic-test-results.txt` in the same folder after every query. The report contains model identity, timing, scores, ranks, and paths relative to the selected root. **Cancel Semantic Test** preserves all completed queries. Rerunning the same model replaces that model's previous report.

Semantic similarity is a retrieval aid, not a statement of fact. Results may be inaccurate, incomplete, biased, or unexpected and should not be used for safety-critical or other high-impact decisions.

## Requirements

- macOS 27 with Xcode 27 installed.
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
- `THIRD_PARTY_NOTICES.md` - notices for CLIP/AI dependencies and model licensing.
