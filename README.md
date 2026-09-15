# RawCullFB

RawCullFB is a macOS SwiftUI photo browser with local CLIP indexing, semantic search, and local Qwen prompts. It browses and previews JPEG, PNG, HEIC/HEIF, TIFF, Sony ARW, and DNG files, and provides recursive semantic search over supported image formats.

## Requirements

- macOS 27 or later
- **Apple Silicon** (M-series) only
- Xcode 27 and Swift 6 to build from source
- The DataComp CLIP model downloaded in the app

## Features

- Add local folders through the macOS folder picker.
- Browse nested folders in a sidebar.
- Generate in-memory thumbnails for supported RAW files, including Sony ARW and DNG, as well as JPEG, TIFF, and PNG files.
- Open a zoom overlay with keyboard navigation, pan, and magnification controls.
- Display available EXIF details such as camera, lens, exposure, ISO, dimensions, and focus point.
- Prefer matching `.jpg` sidecars for RAW full preview images when present.
- Download and verify DataComp CLIP before enabling indexing or search.
- Select an indexed image and use **Find Similar** to rank its nearest visual neighbors.
- Recursively and incrementally index a selected folder into its hidden `.clipbench` directory.
- Search locally with natural-language descriptions and show thumbnail/path results.
- Adjust the semantic result limit in steps of ten (default 50, range 10–500).
- Validate a user-selected Qwen vision-language Core AI bundle and analyze the selected photo locally from the main toolbar.

## CLIP model

RawCullFB supports DataComp CLIP only. It runs entirely on the Mac and performs two jobs: it encodes photographs while building an index, and it encodes a natural-language query so the app can rank matching photographs.

| Model | Model module | What it does |
|---|---|---|
| DataComp CLIP | `CLIP-DataComp` | Uses the LAION/OpenCLIP ViT-B/32 256 px DataComp model for image indexing and semantic search. |

## CLIP workflow

1. Open **RawCullFB > Settings > CLIP**.
2. Download DataComp CLIP, accept its licence terms, and select it.
3. Wait for the model to report a valid verification status.
4. Select the folder that should become the recursive index root.
5. Choose **Index Selected Folder** in the main toolbar. Indexing never starts automatically.
6. Enter a description in the semantic search field and press Return or Search.
7. Double-click a result to inspect its full embedded/rendered JPEG with EXIF information and histogram.

RawCullFB stores one model-specific index at `.clipbench/clip-<model-hash>.clipindex` inside the selected root. Source photographs are not modified. Model inference, embeddings, and search stay on the Mac.

### Semantic test mode

Place a UTF-8 file named `semantictest.txt` in the selected photo-folder root, with one semantic query per line. Empty lines and lines beginning with `#` are ignored. After selecting and indexing a model, choose **Run Semantic Test** in the main toolbar.

RawCullFB executes the queries sequentially using the current result limit and displays each completed result set. It atomically updates `<model-name>-semantic-test-results.txt` in the same folder after every query. The report contains model identity, timing, scores, ranks, and paths relative to the selected root. **Cancel Semantic Test** preserves all completed queries. Rerunning the same model replaces that model's previous report.

Semantic similarity is a retrieval aid, not a statement of fact. Results may be inaccurate, incomplete, biased, or unexpected and should not be used for safety-critical or other high-impact decisions.

## Swift package dependencies

Requirements are pinned to exact versions or revisions in the Xcode project and recorded in `RawCullFB.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`. Revision-pinned dependencies are shown with their complete commit.

| Package (resolved identity) | Resolved pin | Responsibility | Main APIs/products used by RawCullFB |
|---|---:|---|---|
| PhotoAIKit (`photoaikit`) | local package in `Packages/PhotoAIKit` (based on upstream revision `27017a322f7e94e78d7711797dc0a65d577d944f`) | Core AI model discovery and validation, Qwen vision-language loading, CLIP inference, embedding artifacts, multi-object SAM 3 masks, and AI workflow contracts | `CoreAIQwenProvider`, `CoreAICLIPProvider`, `CoreAISAM3Provider`, `PhotoAIContracts`, `PhotoAIWorkflows` |
| [RawParserKit](https://github.com/rsyncOSX/RawParserKit) (`rawparserkit`) | `1.3.0` | RAW metadata, embedded previews, thumbnails, focus-point metadata, and supported-format handling, including Sony ARW and DNG | `RawImageLoader`, `BrowserExifInfo`, `RawFocusPoint` |
| [RawCullCore](https://github.com/rsyncOSX/RawCullCore) (`rawcullcore`) | `1.1.2` | Shared image-analysis utilities | `HistogramCalculator.normalizedLuminanceHistogram` |

The Xcode target also links PhotoAIKit's `CoreAIEfficientSAMBackend`, `CoreAISAM3Backend`, `PhotoAIStorage`, and `VisionFeaturePrintBackend` products. Deep Review uses the SAM 3 backend's composited semantic mask, which includes every object matching the selected prompt.

Resolved transitive dependencies are recorded here as build inputs even though RawCullFB does not import their products directly:

| Resolved identity | Resolved pin | Role in the package graph |
|---|---:|---|
| `coreai-models` | revision `7359dbcf6c3babb4fbfadfd015ffcc1cb6d87420` | Apple Core AI model and conversion support reached through PhotoAIKit |
| `eventsource` | `1.5.1` | Server-sent-event transport used by transitive model tooling |
| `swift-asn1` | `1.7.2` | ASN.1 support reached through the cryptography stack |
| `swift-collections` | `1.6.0` | Collection data structures used by transitive packages |
| `swift-crypto` | `4.5.2` | Cryptographic primitives used by transitive packages |
| `swift-huggingface` | `0.10.1` | Hugging Face model download and metadata support used by model tooling |
| `swift-jinja` | `2.5.1` | Prompt-template rendering used by model tooling |
| `swift-transformers` | `1.3.4` | Tokenizer and transformer support used by the AI package graph |
| `xgrammar` | `0.2.2` | Grammar-constrained generation support used by Core AI language models |
| `yyjson` | `0.12.0` | C JSON engine used by transitive model tooling |

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
