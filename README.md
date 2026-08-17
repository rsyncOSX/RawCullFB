# RawCullFB

RawCullFB is a macOS SwiftUI photo browser with local CLIP indexing and semantic search. It preserves the normal folder browser and zoomable preview while adding recursive semantic search over JPEG, PNG, HEIC/HEIF, TIFF, and Sony ARW files.

## Requirements

- macOS 27 or later
- **Apple Silicon** (M-series) only
- Xcode 27 and Swift 6 to build from source
- A compatible Core AI CLIP model downloaded in the app

## Features

- Add local folders through the macOS folder picker.
- Browse nested folders in a sidebar.
- Generate in-memory thumbnails for supported RAW, JPEG, TIFF, and PNG files.
- Open a zoom overlay with keyboard navigation, pan, and magnification controls.
- Display available EXIF details such as camera, lens, exposure, ISO, dimensions, and focus point.
- Prefer matching `.jpg` sidecars for RAW full preview images when present.
- Download, select, and verify a CLIP model before enabling indexing or search.
- Select an indexed image and use **Find Similar** to rank its nearest visual neighbors.
- Recursively and incrementally index a selected folder into its hidden `.clipbench` directory.
- Search locally with natural-language descriptions and show thumbnail/path results.
- Adjust the semantic result limit in steps of ten (default 50, range 10–500).

## CLIP models

RawCullFB offers two downloadable CLIP models. Both run entirely on the Mac and perform the same two jobs: they encode photographs while building an index, and they encode a natural-language query so the app can rank matching photographs. They differ in their training data and learned weights, so the ordering and scores of the results can differ.

| Model | Model module | What it does |
|---|---|---|
| DataComp CLIP | `CLIP-DataComp` | Uses the LAION/OpenCLIP ViT-B/32 256 px DataComp model for image indexing and semantic search. It can be useful as an alternative retrieval model when its training distribution produces better matches for a catalog. |
| OpenAI CLIP | `CLIP-OpenAI` | Uses OpenAI's CLIP ViT-B/32 model for image indexing and semantic search. This is the default selection. |

Only one model is active at a time. Each model has its own fingerprinted index, so changing models does not mix incompatible embeddings; index the folder with the newly selected model before comparing its search results.

## CLIP workflow

1. Open **RawCullFB > Settings > CLIP**.
2. Download DataComp CLIP or OpenAI CLIP, accept its licence terms, and select it.
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
| [PhotoAIKit](https://github.com/rsyncOSX/PhotoAIKit) (`photoaikit`) | revision `6e3216027b267c27ccaf99d334807b18ea1aaec9` | Core AI model discovery and validation, CLIP inference, embedding artifacts, and AI workflow contracts | `CoreAICLIPProvider`, `SourceFingerprint`, `SimilarityArtifact`, `PhotoAIContracts`, `PhotoAIWorkflows` |
| [RawParserKit](https://github.com/rsyncOSX/RawParserKit) (`rawparserkit`) | `1.2.8` | RAW metadata, embedded previews, thumbnails, focus-point metadata, and supported-format handling | `RawImageLoader`, `BrowserExifInfo`, `RawFocusPoint` |
| [RawCullCore](https://github.com/rsyncOSX/RawCullCore) (`rawcullcore`) | `1.1.2` | Shared image-analysis utilities | `HistogramCalculator.normalizedLuminanceHistogram` |

The Xcode target also links PhotoAIKit's `CoreAIEfficientSAMBackend`, `CoreAISAM3Backend`, `PhotoAIStorage`, and `VisionFeaturePrintBackend` products so the app remains aligned with the shared AI package graph, although the current RawCullFB feature code directly imports only its CLIP, contracts, and workflow products.

Resolved transitive dependencies are recorded here as build inputs even though RawCullFB does not import their products directly:

| Resolved identity | Resolved pin | Role in the package graph |
|---|---:|---|
| `coreai-models` | revision `bffc38fe48f50e4e962ac9772b64a5b55a605286` | Apple Core AI model and conversion support reached through PhotoAIKit |
| `eventsource` | `1.4.2` | Server-sent-event transport used by transitive model tooling |
| `swift-asn1` | `1.7.1` | ASN.1 support reached through the cryptography stack |
| `swift-atomics` | `1.3.1` | Low-level concurrency primitives used by transitive packages |
| `swift-collections` | `1.6.0` | Collection data structures used by transitive packages |
| `swift-crypto` | `4.5.1` | Cryptographic primitives used by transitive packages |
| `swift-huggingface` | `0.9.0` | Hugging Face model download and metadata support used by model tooling |
| `swift-jinja` | `2.4.2` | Prompt-template rendering used by model tooling |
| `swift-nio` | `2.101.3` | Networking and event-loop support used transitively |
| `swift-system` | `1.8.0` | System-call wrappers used transitively |
| `swift-transformers` | `1.3.3` | Tokenizer and transformer support used by the AI package graph |
| `xgrammar` | revision `ba00e8bd4d85be96a2fe8cdc561cb08bed899db6` | Grammar-constrained model tooling resolved from its `main` branch |
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
