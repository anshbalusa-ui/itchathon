# FitCheck 2.0 — Engineering architecture and decision log

**Architecture goal:** native, local-first, testable avatar-first iPhone application.  
**Current implementation:** manual-measurement SwiftUI app on `main`; unmerged experimental LiDAR/Vision capture in draft PR [#5](https://github.com/anshbalusa-ui/itchathon/pull/5).  
**Do not merge #5 until it compiles and passes real-device capture tests.**

## 1. Runtime modules and data flow

```text
Onboarding / create avatar (SwiftUI)
  -> CaptureCoordinator (permissions, front/side sequence, cancellation)
    -> ARKit frame provider (RGB, intrinsics, sceneDepth, confidence)
    -> Vision person segmenter and pose detector
    -> FrameQualityEvaluator / orientation and stability checks
  -> PersonDepthAligner (mask + pose + depth mapping; frame calibration)
  -> BodyGeometryEstimator (derived spans/shape features + provenance)
  -> AvatarParameterMapper (only supported parameters; no made-up shape)
  -> AvatarProfileStore (local, versioned, deletable)
  -> AvatarRenderer (RealityKit or verified compatible SceneKit pipeline)
  -> CatalogRepository (mock now; StoreCatalogAdapter later)
  -> GarmentRenderer (prepared mesh and asset mapping)
  -> FitEstimationService (checked geometry + actual garment dimensions)
  -> FitCopyPresenter (neutral labels or "unknown"; no numbers in UI)
```

**Hard boundary:** avatar rendering and fit inference are separate. A shirt placed over a 3D model does not constitute fit validation. Missing measurements must lead to unavailable estimates, not invented body values.

## 2. The scan contract

```swift
enum CaptureView { case front, side }
enum CaptureStatus { case idle, permission, framing, stable, processing, complete, retryRequired, cancelled, unsupported }
struct FrameEvidence {
    let timestamp: TimeInterval
    // ephemeral in-memory camera frame + depth + confidence + segmentation mask
    // camera intrinsics, image/depth dimensions, orientation and pose landmarks
}
struct ScanEvidence {
    let front: FrameEvidence
    let side: FrameEvidence
    let qualityReport: ScanQualityReport
}
```

These are conceptual contracts, not copy-paste drop-in types. Bind implementation to actual ARKit/Vision APIs. Preserve orientation, sensor intrinsics, raw image size, depth buffer size, and mapping transforms together. Scene-wide depth validity does not prove depth **on the person**.

Required checks before capture:
- LiDAR scene depth is actually supported and available.
- Camera permission is granted.
- Person mask is confidently visible and does not clip the frame.
- Pose keypoints are plausible; handle side-view occlusion rather than requiring all left/right joints.
- The person occupies enough of the frame; background and depth map align with person landmarks.
- Consecutive frames are stable, and front/side orientation is sufficiently distinct (or the app requests retry).
- Reject interrupted AR sessions, stale asynchronous frame results, unsupported modes and degraded depth.

**Risk in PR #5:** its first-pass capture uses whole-scene depth acceptance and textual front/side prompts. Build-to-device and depth-to-mask alignment are explicit first remediation stories, not assumed solved.

The rear LiDAR camera normally faces **away** from the phone holder. Real scans may require another person's help or a stand, and the screen must not promise Face ID-style fully self-serve capture.

## 3. Proposed derived geometry model

```swift
enum DerivedRegion: String, Codable {
    case shoulders, chest, midsection, torsoLength, hips, arms
}
enum EstimateState: String, Codable {
    case observed, approximate, unavailable
}
struct DerivedDimension: Codable {
    var internalMeters: Double?            // never surfaced to the shopper
    var state: EstimateState
    var provenance: String                 // LiDAR+mask / heuristic / absent
    var qualityReason: String?
}
struct AvatarProfileV1: Codable {
    var schemaVersion: Int                 // starts at 1
    var createdAt: Date
    var regions: [DerivedRegion: DerivedDimension]
    var assetID: String
    var morphParameters: [String: Float]   // selected validated avatar adjustments
    var scanMethod: String
}
```

This is a target schema design. Before coding, reconcile names with current `BodyProfile`, `MeasurementOrigin`, and `ProfileStore`. A depth-derived width is **not** an observed circumference. Where a cross-section or missing region must be estimated, it must be explicitly marked approximate or unavailable; never silently promote it to observed.

Profile rehydration must not require saved camera images. Cache derived parameters securely in the app's private container, with deletion and version-safe decoding.

## 4. Avatar model strategy

**Offline model preparation (not an inference model):** use MakeHuman or MPFB2 on a developer's computer/Blender to export an appropriately licensed simplified humanoid base mesh, a compatible shirt template, and tested geometry variants. Then package appropriately optimized assets for iOS.

- MakeHuman application source is AGPL; its bundled core assets and generated output are CC0. MPFB code is GPLv3; its bundled graphical assets and outputs are CC0. Verify every **third-party** asset separately before use.
- Prefer directly importing a small, prepared asset in a format verified to load in the chosen iOS renderer (e.g., USDZ after conversion). Check origin, scale, coordinate axes, rigging, material assignments, mesh density and device performance. Do not assert a rig/morph target survives conversion without testing.
- Parametric avatar personalization is an **engineering capability to build**, not a free feature of a CC0 base mesh. Choose a small set of explicit supported parameter changes and validate against the target mesh.
- Render a neutral stylized avatar and let the customer rotate/zoom it. Avoid photorealistic promises or appearance judgments.
- If scanning fails to provide a reliable parameter, keep it unset or render a clearly illustrative avatar; do not call it exact.

**Explored alternatives:** [MakeHuman](https://github.com/makehumancommunity/makehuman), [MPFB2](https://github.com/makehumancommunity/mpfb2), and the [Apple RealityKit docs](https://developer.apple.com/documentation/realitykit). [SMPL-X](https://github.com/vchoutas/smplx) is not an assumed commercial dependency; its model-license terms require careful review.

## 5. Catalog and garment data

```swift
struct CatalogProduct: Identifiable, Codable {
    var id: String
    var storeProductID: String?            // nil for mock
    var name: String
    var garmentKind: String                // MVP: T-shirt only
    var imageAsset: String
    var renderAssetID: String?             // prepared generic garment asset
    var sizeVariants: [GarmentVariant]
}
struct GarmentVariant: Codable {
    var id: String
    var storeSizeLabel: String
    var finishedGarment: GarmentMeasurements?
    var measurementBasis: String           // finishedGarment / bodySizeChart / unknown
    var source: String
}
```

No invented finished-garment measurements passed off as real product specs. Test mock values must be marked synthetic in developer data and sample screens. A body-size chart cannot be interpreted as finished-garment dimensions.

Create a `CatalogRepository` protocol and `MockCatalogRepository` implementation; do not hardwire UI to Ben's website. Future `BenStoreCatalogAdapter` depends on confirming his ecommerce platform, API access/permission, product photos and actual size chart semantics.

## 6. Fit model and UI copy

Treat the current `FitEngine` as reusable mathematical/reference logic, **not** as a ready-made avatar-first solution: current `evaluate` requires a favorite garment and has scoring heuristics not validated for this new experience.

A new `FitEstimationService` should accept:
- trusted body-derived geometry with per-region availability/provenance;
- selected product and its **finished garment** dimensions per variant;
- configurable calibration/garment ease logic, evaluated in internal tests.

Output:
```swift
enum GarmentFitLabel { case snug, comfortable, relaxed, unknown }
struct GarmentRegionFit {
    var region: String
    var label: GarmentFitLabel
    var confidenceLevel: String  // internal only; do not show percentage
    var rationale: String
}
```

Any numeric thresholds must be **documented, justified and tested** against real fit outcomes before customer-facing claims. During development a synthetic sample can exercise the pipeline, but it must say illustrative/demo and must not masquerade as validated retail advice. If the scan/garment data cannot support a claim, return `.unknown`.

UI mapping examples:
- `snug` → "Closer fit at the shoulders"
- `comfortable` → "Regular fit through the chest" (when evidence supports it)
- `relaxed` → "Roomier through the chest"
- `unknown` → "Not enough information to estimate this area"

Do not display meters, centimeters, inches, signed scores, confidence percentages, or body ratings.

## 7. Local privacy architecture

- Camera frames, segmentation masks and depth maps remain ephemeral in memory and are not transmitted, logged or committed.
- Derived profile persists locally by explicit user action; accessible delete and rescan controls. Check camera cancel/interruption and app backgrounding for clean release.
- No third-party 3D body-generation web APIs for the first MVP.
- App assets are generic character meshes, not recordings of users.
- Any developer testing involving people requires consent, appropriate clothing, and no identifying image storage without explicit permission.
- Consider the sensitivity of body profiles in all future analytics/cloud synchronization plans; those features are out of scope.

## 8. Tests and validation gates

| Gate | Evidence expected | If failing |
| --- | --- | --- |
| G0 baseline | XcodeGen project builds on target Xcode, existing tests pass | Fix branch before layering features |
| G1 guided capture | Real LiDAR iPhone: front/side capture, permission, no-person, cropped, motion, loss of depth, cancel/retry | Rework capture gating |
| G2 geometry | Person-depth alignment verified visually **in developer debug tooling only**; repeated scans compared under controlled conditions | Mark unsupported regions unavailable |
| G3 avatar assets | Imported mesh renders on device and scan-supported parameter changes clearly affect geometry | Fall back to illustrative generic asset |
| G4 persistence | Profile rehydrates after termination and is removed completely on delete | Block release |
| G5 catalog/try-on | Switch garment and variant, no stale visual, representative asset licensed | Fix asset mapping |
| G6 fit labels | Unit cases include missing/mislabeled garment data and uncertain scan; no unsupported claim | Return `unknown` |
| G7 journey | UI test: scan → avatar → catalog → selected garment → fit feedback; accessibility/VoiceOver states | Block MVP sign-off |

**No numerical accuracy target is adopted before preliminary repeatability/reference measurement tests.** Accuracy cannot be inferred from simulation/unit tests alone.

## 9. Development environments

- Mac with Xcode supporting deployment target iOS 17+, XcodeGen from existing `project.yml`.
- Physical LiDAR iPhone Pro and a safe stable location, ideally a helper or phone mount.
- Offline Blender + MakeHuman/MPFB for permitted 3D asset preparation.
- RealityKit/SceneKit (choose renderer after a minimal on-device asset proof).
- No mandatory cloud service or paid 3D API.
- Keep implementation on feature branches and use draft PRs; no silent merges into `main`.
- Run `xcodegen generate`, inspect `xcodebuild -showdestinations`, then run the repository test scheme. Do not claim builds/tests passed without their command output.

## 10. Engineering milestones and fallback rules

- **Week 1:** baseline compiles, depth/person pipeline verified on-device, basic geometry evidence created, a licensed 3D base mesh loads. If reliable person-specific geometry is not possible, build an honestly illustrative avatar rather than faking personalization.
- **Week 2:** local avatar profile, mock catalog, garment rendering, conservative fit labeling, smooth avatar-first UI, testing and demo. If real garment evidence is inadequate, show visualization and `unknown` fit state instead of inventing a recommendation.

Keep demo and production validation labels separate. The MVP is for feasibility learning, not a validated fit technology claim.

## 11. References

- Apple scene depth: https://developer.apple.com/documentation/arkit/arconfiguration/framesemantics-swift.struct/smoothedscenedepth
- Apple people occlusion: https://developer.apple.com/documentation/arkit/occluding-virtual-content-with-people
- MakeHuman license: https://github.com/makehumancommunity/makehuman/blob/master/LICENSE.md
- MPFB license: https://github.com/makehumancommunity/mpfb2/blob/master/LICENSE.md
- Existing project: https://github.com/anshbalusa-ui/itchathon

See [requirements](AVATAR_MVP_REQUIREMENTS.md), [stories](AVATAR_MVP_STORIES.md), and [prompts](AVATAR_MVP_AGENT_PROMPTS.md).
