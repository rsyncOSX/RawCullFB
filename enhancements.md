# Enhancing SAM 3 and Qwen in RawCullFB

The best direction is to turn the three models into a staged photo-culling pipeline rather than exposing them as three independent tools:

```text
CLIP → find/group candidates
SAM 3 → objective subject/detail analysis
Qwen → semantic and compositional assessment
       ↓
combined per-photo result and ranking
```

## What RawCullFB currently does

SAM 3 already supports multiple selected photos: select photos with Command/Shift, then choose **Deep Review**. The selection is passed to Deep Review in `BrowserGridView.swift`.

There are two important limitations:

- If the selection contains more than 12 photos, Deep Review silently analyzes only the first 8.
- Qwen operates only on `selectedFile`, not `selectedFiles`.

## Highest-value SAM 3 improvements

### 1. Activate the data that Deep Review already supports

Currently every candidate is created with:

- `normalSharpnessScore: nil`
- `subjectLabel: nil`
- `normalizedAFPoint: nil`

This means:

- SAM’s automatic prompt selection almost always falls back to `.subject`.
- The existing “AF point inside subject” calculation is unused.
- Normal sharpness cannot be compared with subject-specific sharpness.

Populate these from:

- CLIP zero-shot labels such as person, bird, animal, car, landscape.
- `RawImageMetadata.focusPoint`.
- A cheap whole-image sharpness pass.

This alone would make the existing Deep Review substantially more useful.

### 2. Make the candidate limit explicit and configurable

Offer:

- **Fast:** preselect 8 candidates.
- **Full:** analyze every selected photo.
- **Automatic:** cheap sharpness/duplicate filtering first, then SAM on the strongest 8–12.

For hundreds of photos, Automatic is preferable. SAM should not process every near-identical frame if a cheap first pass can discard obviously blurred candidates.

### 3. Improve multi-object handling

The current Deep Review scores the composited mask containing all objects that match the prompt. For multiple people or animals, that can hide important differences.

Ideally, PhotoAIKit should return individual SAM instances in addition to the composite mask. RawCullFB could then support policies such as:

- Portrait: prioritize the largest or central face.
- Group: use the weakest face or lowest face-detail score.
- Wildlife: prioritize the head or eye region.
- Sports: prioritize the subject nearest the AF point.

If individual instances are unavailable, calculate connected components from the composite mask as an intermediate solution.

## Batch Qwen analysis

Add an **Analyze Selection** operation that iterates over `selectedFiles`. Do not combine dozens of images into one large visual prompt. Analyze each photo independently, then combine their small structured results.

Instead of storing a free-form string, have Qwen produce something like:

```swift
struct QwenPhotoAssessment: Codable, Sendable {
    let subject: String
    let compositionScore: Int       // 1...5
    let exposureScore: Int          // 1...5
    let subjectVisibilityScore: Int // 1...5
    let eyesOpen: Bool?
    let problems: [String]
    let strengths: [String]
    let confidence: Float
}
```

Use constrained or typed generation if supported by the installed Core AI model. Otherwise request strict JSON and validate it. This gives sortable columns instead of prose that is difficult to compare.

For each photo, give Qwen:

- The complete image.
- A SAM-derived subject crop, if multiple attachments are supported.
- Basic EXIF facts.
- SAM measurements such as mask confidence and coverage.

The subject crop is especially valuable because Qwen’s configured visual input is relatively small; faces and eyes can otherwise occupy very few pixels.

Qwen should assess semantic qualities—expression, pose, obstruction, composition and exposure. SAM/local image processing should remain authoritative for precise sharpness.

## Combining the analyses

Initially use a transparent rule-based score, not Qwen for the entire decision:

```text
Technical score     60%  SAM subject-detail score
Composition         25%  Qwen structured score
Exposure/visibility 15%  Qwen structured score
```

Then apply explicit warnings or penalties for:

- No reliable SAM mask.
- Very low mask confidence.
- Background sharper than subject.
- Face or eyes obscured or closed.
- Severe clipping or poor exposure.

If a component is unavailable, renormalize the remaining weights rather than treating the missing value as zero. Compare scores only within the same scene or burst; scores across unrelated photographs are generally not meaningful.

Use CLIP primarily for grouping and retrieval, not as a quality score:

- Find visually similar frames.
- Form candidate groups.
- Infer a coarse subject label for SAM.
- Let SAM and Qwen choose within each group.

## Recommended workflow

A scalable combined operation would be:

1. Select a folder or many photos.
2. CLIP groups similar frames or identifies candidate bursts.
3. A cheap sharpness pass removes obvious failures.
4. SAM analyzes subject masks and subject-specific detail.
5. Generate a subject crop from the SAM mask.
6. Qwen analyzes the full frame and subject crop using structured output.
7. Combine scores and display a table with score breakdowns.
8. Let the user filter to recommended, needs review, and reject.

Run SAM and Qwen sequentially initially. Local models can consume substantial unified memory, and parallel generations may reduce throughput or cause memory pressure. The app can still expose progress, cancellation, resume and retry.

## Persistence is important

Batch analysis becomes much more useful when results survive a rescan. `BrowserFileItem` currently creates a new random UUID each time it is constructed.

For cached analysis, use a stable key derived from:

- Relative file path.
- File size and modification date.
- Optionally a lightweight content hash.
- Model identity and version.
- Prompt and schema version.

Store Qwen JSON, SAM scores, mask references and the combined result in a small database or analysis file beside the CLIP index.

## Suggested implementation order

1. Populate SAM subject label, AF point and normal sharpness.
2. Replace the hidden 8-photo cutoff with Fast/Full/Automatic modes.
3. Add structured Qwen batch analysis with progress and cancellation.
4. Add the combined results table and deterministic score.
5. Add SAM-derived subject crops to Qwen.
6. Extend SAM multi-object results to individual instances.

The first three changes deliver most of the practical improvement without requiring a major redesign.
