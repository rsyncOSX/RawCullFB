# PhotoAIKit

Reusable Core AI CLIP, fixed-resolution SigLIP 2, EfficientSAM, SAM3, and Qwen code extracted from RawCullSAM3. The package owns model inference, typed contracts, reusable indexing/segmentation workflows, and optional storage. It does not contain RawCull view models, UI, RAW-file decoding, helper-process behavior, or culling policy.

## Requirements

- Xcode 27 or newer (`swift-tools-version: 6.4`)
- macOS 27 or newer
- Swift 6 language mode

The package pins the same `apple/coreai-models` revision used by the source application. It does not embed any `.aimodel`, `.aimodelc`, tokenizer, or model metadata resources.

## Products

- `PhotoAIContracts`: model identities and verified fingerprints, capability/factory contracts, source values, typed image and text similarity values, segmentation/embedding types, provider/store/decoder protocols, and URL-based model-bundle validation.
- `CoreAICLIPBackend`: actor-owned CLIP and fixed-resolution SigLIP 2 image preprocessing, text tokenization, Core AI inference, and image/text comparison.
- `CoreAIEfficientSAMBackend`: actor-owned EfficientSAM point/grid inference and highest-confidence subject-mask adaptation.
- `CoreAISAM3Backend`: actor-owned SAM3 tokenization, inference, exhaustive semantic-mask decoding, and multi-instance fallback.
- `CoreAIQwenBackend`: validation and loading of Qwen Core AI text and vision-language models through Foundation Models sessions.
- `VisionFeaturePrintBackend`: actor-owned Vision feature-print generation, opaque artifact coding, and native distance calculation.
- `PhotoAIWorkflows`: bounded vector/opaque artifact indexing, configurable fallback, cosine similarity, segmentation preprocessing/batching, versioned batch transport, mask cataloging, prompt fallback, best-mask selection, geometry, and quality classification.
- `PhotoAIStorage`: injected memory/disk mask stores, current descriptor-complete artifact codecs, and legacy embedding readers.

## Model URLs

The host application locates, downloads, bookmarks, or otherwise manages models. It then passes each bundle URL directly to the backend:

```swift
import CoreAICLIPBackend
import CoreAIEfficientSAMBackend
import CoreAISAM3Backend
import CoreAIQwenBackend
import FoundationModels

let clip = try CoreAICLIPProvider(modelBundleURL: clipBundleURL)
let efficientSAM = try CoreAIEfficientSAMProvider(modelBundleURL: efficientSAMBundleURL)
let sam3 = try CoreAISAM3Provider(modelBundleURL: sam3BundleURL)
let qwenProvider = try CoreAIQwenProvider(modelBundleURL: qwenBundleURL)
let qwen = try await qwenProvider.makeVisionLanguageModel()
let session = LanguageModelSession(model: qwen)
let response = try await session.respond {
    Attachment(photo)
    "Describe this photo's composition."
}
print(response.content)
```

Hosts with ordered candidate URLs can use the shared capability and factory API:

```swift
let capability = CoreAICLIPProvider.factory.capability(in: candidateURLs)
let clip = try CoreAICLIPProvider.factory.makeFirstAvailable(in: candidateURLs)
```

`ModelCapabilityStatus` contains no display wording or application path policy.

A bundle URL is expected to contain:

```text
ModelBundle/
├── metadata.json              # assets.main names the selected model asset
├── tokenizer/                # required by CLIP, SigLIP 2, SAM3, and Qwen; omitted by EfficientSAM
│   ├── tokenizer.json
│   └── tokenizer_config.json # additionally required by Qwen
├── selected-model.aimodel     # assets.main; or .aimodelc
├── embedding.aimodel          # Qwen VLM bundles only
└── vision.aimodel             # Qwen VLM bundles only
```

New exports also include `asset_fingerprints.main`. `ModelBundleResolver`
cryptographically verifies this value. Older bundles remain valid and receive a
size/modification-time fallback fingerprint; `ModelIdentity.cacheIdentifier`
keeps its existing behavior while `artifactIdentifier` is the fingerprinted key
for new artifacts.

No default Application Support path, `Bundle.main` lookup, or package resource fallback is used.

CLIP metadata version 0.4 makes the model contract explicit: architecture,
pretrained checkpoint, embedding dimensions, tokenizer context, input
resolution, resize/crop/interpolation, normalization, and named Core AI
functions. The provider still accepts older PhotoAIKit bundles as the original
224-pixel stretch baseline. New exports use the model-correct shortest-side
resize followed by a center crop.

SigLIP 2 bundles use the same metadata envelope with `family: siglip2`, a
64-token Hugging Face tokenizer JSON, fixed 256×256 stretch preprocessing, and
their own backend identity. This prevents SigLIP 2 artifacts from being mixed
with CLIP artifacts even when both have 768 dimensions.

## Host integration

Map the app's photo type to `AIImageSource`, provide an `ImageDecoding` adapter, and inject model/cache URLs:

```swift
import PhotoAIContracts
import PhotoAIStorage
import PhotoAIWorkflows

let source = AIImageSource(
    id: photo.id,
    url: photo.url,
    displayName: photo.name
)

let memory = SubjectMaskMemoryStore()
let disk = try SubjectMaskDiskStore(cacheDirectory: appMaskCacheURL)
let maskConfiguration = SubjectMaskRepositoryConfiguration(
    defaultPrompt: .subject,
    modelIdentity: sam3.modelIdentity,
    inputMaxSide: 4_320
)
let cachedMasks = SubjectMaskRepository(
    configuration: maskConfiguration,
    stores: [memory, disk]
)
let service = SegmentationService(
    provider: sam3,
    stores: [memory, disk],
    maxSide: 4_320
)

let result = try await service.segment(
    image: decodedImage,
    source: source,
    prompt: .subject
)
```

SAM3 results expose one composited mask containing every subject that matches
the selected prompt. The backend uses the model's exhaustive semantic
probability map when available and otherwise unions all decoded instance masks.

For CLIP indexing, inject the host decoder and choose fallback explicitly:

```swift
let indexer = EmbeddingIndexer(
    primaryProvider: clip,
    fallbackProvider: optionalHostFallback,
    decoder: rawAwareDecoder,
    fallbackPolicy: .wholeBatch,
    concurrencyLimit: 2
)

let index = try await indexer.index(sources)
```

For a package-owned CLIP-to-Vision fallback, use descriptor-complete artifacts:

```swift
import VisionFeaturePrintBackend

let vision = VisionFeaturePrintBackend()
let indexer = SimilarityArtifactIndexer(
    primaryProvider: clip,
    fallbackProvider: vision,
    decoder: rawAwareDecoder,
    fallbackPolicy: .wholeBatch,
    concurrencyLimit: 2
)
let artifacts = try await indexer.index(sources)
```

`SimilarityArtifactDescriptor` records backend, model fingerprint, dimensions,
representation, preprocessing, normalization, configuration, source fingerprint,
and schema version. Vision observations stay opaque; comparison goes through
`VisionFeaturePrintBackend.distance(from:to:)`.

`EmbeddingCodec.encode(EmbeddingArtifact)` is the current CLIP persistence API.
The former identity-incomplete writers remain callable but are deprecated.
`decodeMigrating` accepts both version-1 formats against the real current model
identity and marks the result for immediate rewrite.

For semantic queries, encode text with the same provider that produced the
image artifacts, then compare through the backend-owned primitive:

```swift
let query = try await clip.embedding(for: "a bird in flight")
let score = try clip.similarity(image: persistedArtifact, text: query)
```

`TextEmbedding` is query-scoped and is not a file-backed
`SimilarityArtifact`. Its descriptor carries the complete backend identity,
dimensions, tokenizer version, and schema. The comparator rejects Vision
artifacts and every mismatched CLIP model/configuration field before decoding
the opaque image payload. Its result is cosine similarity in `-1 ... 1`, where
higher values are closer semantic matches.

The exported CLIP graph owns L2 normalization of `text_embeds`.
`CoreAICLIPProvider` validates that output as finite, non-empty, correctly
shaped, and normalized; it does not normalize the text vector again.

For SAM workflows, `SubjectMaskCatalogIndex` builds incremental package-owned
inventory, while `SubjectMaskSelector` implements ordered prompts, minimum
quality/confidence, best-mask selection, and cache-only or generate-if-missing
acquisition. `SegmentationBuildTransportCodec` provides a versioned JSON-lines
event schema for helper processes.

`CoreAIEfficientSAMProvider` adapts EfficientSAM's point-only runtime to the
same `SubjectSegmenting` contract. It sends an empty `PointQuery`: a Q=1 model
export uses its single center point, while a perfect-square multi-query export
uses the runtime's regular point grid. The provider returns the highest-scoring
mask and preserves the requested prompt in diagnostics, although EfficientSAM
does not semantically interpret that text. For unattended subject discovery,
prefer an export with `--num-queries 64 --num-pts 1`.

## Model export tools

Package-neutral developer tools live under `Tools`. Output locations are always
explicit and no script defaults to an application resource directory:

```sh
uv run Tools/export_clip.py \
  --model openclip-datacomp \
  --output-dir /path/to/models \
  --bundle-name CLIP-DataComp

uv run Tools/export_clip.py \
  --model openai \
  --output-dir /path/to/models \
  --bundle-name CLIP-OpenAI

uvx --from huggingface-hub hf download \
  google/siglip2-base-patch16-256 \
  --revision 3f9f96cb90da5dbc758b01813f2f6f1aee24c1ab \
  --local-dir /path/to/models/SigLIP2-Base-Patch16-256/source

uv run Tools/export_siglip2.py \
  --source-dir /path/to/models/SigLIP2-Base-Patch16-256/source \
  --output-dir /path/to/models/SigLIP2-Base-Patch16-256 \
  --overwrite

uv run Tools/export_sam3.py --output-dir /path/to/models
python3 Tools/select_sam3_asset.py sam3_float16.aimodel \
  --bundle-dir /path/to/models/SAM3
```

The CLIP exporter supports the existing OpenAI
`clip-vit-base-patch32` model and OpenCLIP `ViT-B-32-256` with
`datacomp_s34b_b86k` weights. It exports `image_encoder` and `text_encoder` as
two named functions in one Core AI asset and verifies that OpenCLIP and the
saved PhotoAIKit tokenizer produce identical token IDs. Export and selection
write the fingerprint manifest consumed by `ModelBundleResolver`.

The SigLIP 2 exporter pins Google's Apache-2.0
`siglip2-base-patch16-256` checkpoint and emits normalized 768-dimensional
`image_encoder` and `text_encoder` functions. The
`generate_clip_reference.py --model siglip2` command creates PyTorch fixtures
for the opt-in CoreAI parity test.

## Deliberate host responsibilities

- model download/install UI and model URL selection;
- security-scoped bookmarks and sandbox access;
- RAW decoding (for example RawParserKit) and ImageIO fallback;
- SwiftUI/Observation state and display text;
- “latest selection wins” behavior;
- burst grouping, saliency penalties, sharpness/rating decisions;
- SAM3 helper-process launch, parent-process coordination, and app restart.

See [Documentation/ExtractionMap.md](Documentation/ExtractionMap.md) for the complete source-to-package audit.
