# FitCheck — Friday Demo D1

The D1 baseline below is retained as historical verification and media evidence. The **requested human-avatar refinement** at the end supersedes its blocky showcase artwork, clothing meshes and “3D Avatar” link title. Use the current branch's launch helper; its prebuilt-app checks intentionally reject old D1 bundles without the human assets.

## Scope and base

- Repository: `anshbalusa-ui/itchathon`.
- Exact S2C base: `235bee6a5cd7b334d4689ad6e09ff9f4080acb16`.
- Implementation branch: `feature/friday-visual-demo-d1`.
- Intended review target: `feature/lidar-reconstruction-replay-s2c`, not `main`.
- PR #21 and all existing stacked PRs are outside this segment; no merge is performed.

## Entry and meeting journey

Debug supports exactly `-fitcheck-demo-internal`. The existing internal development hub also has **FitCheck Demo Showcase**. Conflicting internal flags fail closed to the legacy home; Release ignores the demo flag and contains no demo screens.

1. Open FitCheck Demo Showcase: a live Metal mannequin wears the Navy Everyday Tee immediately after scene preparation.
2. Drag, or use Left / Right / Reset. Toggle **Show garment** to inspect the generic mannequin.
3. Scroll **Sample collection**. Select Weekend Tee to change the actual shirt material to Sage; select Geometric Vest Concept to load the reviewed file-backed vest. S/M changes the label, not the physical geometry.
4. Open **3D Avatar** under **Explore the technology**. Shape A/B generates distinct authored synthetic partial surfaces, rendered by the same Metal infrastructure. Rotate/reset either shape.
5. Return, then open **LiDAR Reconstruction Demo**. Replay A/B runs the existing reviewed synthetic front/side depth reconstruction and shows distinct partial surfaces. Rotate/reset; Back returns to the selected clothing showcase.
6. Back from a hub-opened showcase returns to the internal hub. Reopening starts the predictable default collection selection. Backgrounding releases scene resources and foregrounding restores the selected view through existing model lifecycles.

There is no automatic navigation, camera request, checkout, network service, personal-profile promotion, or storage operation in this journey. The original scanner, diagnostic labs and save/load/delete controls remain available independently.

## Approved fictional collection

| Product | Color | Size labels | Variant IDs | Rendered source |
| --- | --- | --- | --- | --- |
| Everyday Tee | Navy | S / M | `everyday-navy-small`, `everyday-navy-medium` | Existing procedural shirt |
| Weekend Tee | Sage | S / M | `weekend-sage-small`, `weekend-sage-medium` | Same shirt geometry, Sage material |
| Geometric Vest Concept | Navy | S / M | `geometric-vest-navy-small`, `geometric-vest-navy-medium` | Reviewed bundled `.fitmesh` vest |

All product IDs are scoped to the existing `sample-studio` synthetic fixture, not a real retailer. `FridayDemoSelection` decodes the real `SyntheticCatalog`, resolves every displayed selection through `CatalogPreviewAssociation`, and fails closed if any required sample is unavailable, malformed or unverified. Unsupported choices remove the old preview rather than showing stale success. Product descriptions are authored fictional descriptions; no photography placeholders, prices, availability promises or commercial assets are shown.

## Genuine geometry versus illustration

- Every scene is a real native `MTKView`, with existing Metal shaders, lighting, depth testing, CPU meshes and GPU vertex/index buffers. No static image or video substitutes for app rendering.
- The clothing scene uses the existing generic mannequin and reviewed procedural/bundled garments. It is an illustration, not a measured person, fitted clothing, physical simulation or verified size recommendation.
- Avatar A/B comes from the existing S2A synthetic section-generation authorization. Vertex positions differ. Unknown regions and ends remain open; it is not a complete captured anatomical body.
- Replay A/B comes from S2C first-party simulated depth/confidence/mask rasters, calibration, poses, unprojection, spatial mapping and reconstruction. No recorded person or live LiDAR observation is involved.
- S2A authorization, S2B artifact admission, S2C replay admission, scanner safety and protected profile/storage behavior are unchanged. No synthetic result is saved as a personal avatar.

## Launch

From the repository root:

```bash
Scripts/launch_friday_demo.sh
```

Requirements: macOS with Xcode selected, an installed iPhone Simulator runtime, XcodeGen and Python 3. No developer account, phone or signing credentials are used. The helper prefers a booted available iPhone, otherwise selects an available iPhone; it never erases a simulator. Derived data defaults outside Git. Use `--simulator UDID` for an exact device, `--derived-data PATH` for a build location, or `--app PATH` for a retained Debug simulator app. A prebuilt app must identify as FitCheck/iPhoneSimulator and contain the demo Debug marker and reviewed development asset; Release/device apps are rejected.

In Xcode: open `FitCheck.xcodeproj`, select **FitCheck / Debug / iPhone Simulator**, add only `-fitcheck-demo-internal` under Run → Arguments, then Run.

## Meeting explanation and limitations

> FitCheck already demonstrates synthetic depth-to-3D reconstruction and interactive 3D clothing previews. Real-device LiDAR validation is still pending.

This is a progress demonstration, not a production launch. No physical LiDAR device test, personal-avatar accuracy, garment measurements, commercial inventory or fit acceptance is claimed. Both size labels share geometry. Remaining work requires real-device scanner validation, authorized body-avatar and garment data, and separate physical fit validation; none is fabricated for this demo.

If the graphical Simulator is unavailable during the meeting, use the retained simulator recording and original screenshots described in the evidence section. They show the actual Debug app, not generated mockups. The launch helper cannot provide interactive 3D without a working Simulator/Metal environment; its failure is reported rather than replaced by a fake scene.

## Rendering and accessibility implementation

The demo injects `fitSurface: true` only when constructing authorized avatar/replay scenes. A bounding sphere derived from the admitted renderer mesh frames every allowed orbit and viewport aspect without scaling or rewriting CPU/GPU vertices. Standard renderer labs, catalog scenes and artifact-loaded geometry retain their original camera behavior. A projection regression checks all four A/B sources across narrow/wide aspects and orbit limits, including near/far clipping and exact GPU vertex preservation.

At accessibility text sizes, the clothing page omits its redundant decorative brand header and reserves a 220-point scene so scrollable controls remain usable. Synthetic A/B choices stack vertically. Rotation buttons remain alternatives to gestures. Scene creation and garment-load failures have explicit retry controls and do not display a stale replacement mesh.

The focused D1 development run at `~/fitcheck-d1-artifacts/demo-refined.xcresult` passed **8/8** tests with zero failures, skips or expected failures. This is focused evidence, not the complete regression result.

## Preserved development failures

Evidence is retained outside Git under `~/fitcheck-d1-artifacts/`:

- `full-verification/verification-iuwzvfq2`: 328 unit tests passed; UI runner failed before test execution while waiting for AX initialization.
- `isolated-ui.xcresult` and `isolated-ui-diagnostics/`: a dedicated Simulator's cold startup failed migration and RunningBoard terminated XCTest during its initialization assertion. This was not an app test pass.
- `warmed-ui.xcresult`: automation exposed SwiftUI identifier propagation onto the Metal scene; the identifier was moved from the showcase group to its header.
- `demo-focused.xcresult`: the real journey rendered all required scenes, but control-reachability assertions failed. The app's largest-text header/viewport layout and the test's overshooting scroll gestures were corrected; assertions were retained.
- `demo-refined.xcresult`: 8/8 focused D1 checks passed after those fixes.
- `full-verification/verification-6neaxjfm`: 357/358 Debug tests passed, zero skips. The old catalog's missing-information case caught shared fixture description modification. The original catalog was restored; authored Friday-only copy now belongs to `FridayDemoProduct` and cannot change catalog missing-data behavior.

No existing test was deleted, skipped or weakened for this segment. Cold Simulator/host startup has been unreliable on this machine; warm the Simulator with the helper before presenting, and keep the verified screenshots/video available as fallback.

## Fresh complete verification

Final full runner evidence: `/Users/anshbalusa/fitcheck-d1-artifacts/full-verification/verification-1_j24l59/verification.json`.

```bash
caffeinate -disu python3 Scripts/verify_development.py \
  --simulator C07CEE05-AE0B-45B3-9E8F-09C20FCBD5B1 \
  --output-root /Users/anshbalusa/fitcheck-d1-artifacts/full-verification
```

| Check | Fresh result |
| --- | --- |
| Clean Debug unit suite | 329/329 |
| Full Debug simulator UI suite | 29/29 |
| Total Debug | **358/358** |
| Unsigned generic iPhone SDK compilation | PASS |
| Normal Release simulator build | PASS; `ENABLE_TESTABILITY=NO` |
| Release isolation unit suite | 9/9 |
| Release isolation UI suite | 8/8 |
| Total Release isolation | **17/17** |
| Debug positive-control / normal Release marker inspection | PASS |
| Four app bundles' resources and privacy declarations | PASS |

Zero skipped tests or expected failures. The runner verifies every requested Release selector executed and inspects actual Mach-O binaries, the exact reviewed vest digest, development-resource exclusion and runtime artifact/replay resource absence. Privacy manifests remain no-tracking/no-collected-data with existing approved API reasons.

Verified build/test input SHA-256: `f555c8b843a1cc3e0182e0b217493e912bafbb80d3dff2bcfb6954fc988ce1fa`.

`~/fitcheck-d1-artifacts/regression-inventory.json` compares actual executed identifiers against S2C: **all 349 prior Debug tests and all 15 prior Release-isolation tests are represented**, with no missing identifiers. D1 adds nine Debug cases and two Release-isolation cases.

## Original simulator screenshots

All files below are unedited PNG bytes exported from the passing complete run. `FridayScreenshots/manifest.json` retains XCTest timestamps and device IDs; `index.json` maps friendly names to original UUID files and SHA-256 digests. The screenshots were visually inspected.

Evidence root: `/Users/anshbalusa/fitcheck-d1-artifacts/FridayScreenshots/`.

| Required screen | File |
| --- | --- |
| FitCheck Demo Showcase / mannequin and clothing | `01-showcase.png` |
| Rotated mannequin and clothing | `02-rotated-clothing.png` |
| Second garment: bundled Navy vest | `03-second-garment.png` |
| Synthetic avatar A | `04-avatar-a.png` |
| Synthetic avatar B | `05-avatar-b.png` |
| Synthetic LiDAR reconstruction A | `06-lidar-result.png` |
| Clean return to selected showcase | `07-return-showcase.png` |
| Additional synthetic LiDAR reconstruction B | `replay-b.png` |

The same export includes three largest-accessibility screenshots under their original UUID names. These depict real generated/rendered surfaces and reachable controls, not just titles.

## Verified launch and recording backup

The exact simplest command `Scripts/launch_friday_demo.sh` completed successfully: unsigned Debug build, install and direct demo launch on **iPhone 17 FitCheck D1 / iOS 26.5**, UDID `C07CEE05-AE0B-45B3-9E8F-09C20FCBD5B1`. Its default build cache is outside the repository. A retained verified app also supports:

```bash
Scripts/launch_friday_demo.sh \
  --simulator C07CEE05-AE0B-45B3-9E8F-09C20FCBD5B1 \
  --app /Users/anshbalusa/fitcheck-d1-artifacts/full-verification/verification-1_j24l59/DebugDerived/Build/Products/Debug-iphonesimulator/FitCheck.app
```

The helper was also exercised against a Release app, missing argument, unknown option and repository-local derived-data path; all were rejected with useful errors.

| Actual recording | Location | Inspected duration |
| --- | --- | --- |
| Meeting backup, accelerated continuous journey | `/Users/anshbalusa/fitcheck-d1-artifacts/friday-demo-55s.mp4` | **55.000 seconds** |
| Original unmodified Simulator recording | `/Users/anshbalusa/fitcheck-d1-artifacts/friday-demo-original.mov` | 331.807 seconds |

Both are real 1206×2622 Simulator video, not generated animation. The meeting file trims the launch/test-harness lead-in and later stress checks, and accelerates the continuous 175.493-second presentation segment by approximately **3.19×**. This is not a real-time performance claim. The original is retained.

Capture used `xcrun simctl io … recordVideo --codec=h264`, while the genuine XCTest journey exercised the app. `recorded-journey.xcresult` passed **1/1**, with no skips; `RecordingCheckpoints/manifest.json` retains the matching real screenshots/timestamps. AVFoundation decoded and inspected the output's duration/resolution and frames, including exact steady-state LiDAR A/B geometry and clean return. `MeetingVideoInspection/inspection.json` and `VideoCheckpointInspection/inspection.json` retain that inspection metadata and decoded frames.

Meeting fallback, without interactive Simulator graphics:

```bash
open /Users/anshbalusa/fitcheck-d1-artifacts/friday-demo-55s.mp4
open /Users/anshbalusa/fitcheck-d1-artifacts/FridayScreenshots/01-showcase.png
```

Use screenshots 04/05 to explain the distinct synthetic avatar shapes and 06 / `replay-b.png` for reconstruction. The disclaimer remains: real-device validation and verified physical fit are pending.

## Additional screen and appearance review

| Simulator | Actual screenshot size | Appearance | Additional D1 UI result |
| --- | --- | --- | --- |
| iPhone 17 | 1206×2622 | Light | Included in complete passing run |
| iPhone 17e | 1170×2532 | Light | **3/3**, zero skips |
| iPhone 17 Pro Max | 1320×2868 | Dark | **3/3**, zero skips |

Both additional runs exercised direct launch, the full rendered journey/product changes, navigation/lifecycle recovery and the largest accessibility category (`UICTContentSizeCategoryAccessibilityXXXL`). Source and tests were unchanged from the complete verified run.

- Smaller-screen evidence: `~/fitcheck-d1-artifacts/small-light.xcresult` and `SmallLightScreenshots/manifest.json`.
- Large dark evidence: `~/fitcheck-d1-artifacts/large-dark.xcresult` and `LargeDarkScreenshots/manifest.json`.

Actual screenshots of the main showcase, distinct synthetic geometry and reconstruction were inspected for framing, contrast, readable controls and navigation. Largest-type controls are intentionally in a vertically scrollable region; they do not have to fit simultaneously. The scene remains visible while controls scroll. The studio-lit Metal canvas remains light in dark appearance so the same geometry/material lighting stays legible, while native navigation, cards, typography and controls follow dark mode.

No remaining blocker was observed in the verified Simulator journey. Known limits remain cold Simulator startup on this host, generic low-poly fixture artwork, shared size geometry, partial synthetic surfaces and no physical-device accuracy/fit validation. This is meeting-ready progress evidence, not commercial or hardware acceptance.

## Final implementation and draft review

- Final verified implementation commit: `f4b03ef611670eda7e79c1c77c01caa6ccf2c682`.
- Published branch: `feature/friday-visual-demo-d1`.
- Draft PR: [#22 — D1: Friday Demo Showcase with verified native 3D journey](https://github.com/anshbalusa-ui/itchathon/pull/22).
- PR base: `feature/lidar-reconstruction-replay-s2c`.

A documentation-only commit records this review identity after the implementation commit; it changes no verified build/test input. The exact delivered branch-tip SHA is recorded in `/Users/anshbalusa/fitcheck-d1-artifacts/delivery.json` and the PR head. PR #21 remains draft against `main`; no existing PR or branch was merged or modified.

## Requested human-avatar refinement

- Implementation branch: `feature/human-avatar-inspection-d2`.
- Exact D1 base: `40cee194750647657783e9eac622cc997dcb3f2e`.
- The primary Friday showcase now renders a smooth anatomical A-pose human with a detailed head, continuous torso/limbs, hands/fingers and feet through the existing native Metal renderer. This is an authored generic illustration, not a reconstructed or measured person.
- The source is the CC0 MakeHuman base mesh pinned by immutable repository commit and SHA-256 in [NOTICE](../DevelopmentAssets/HumanShowcase/NOTICE.txt). Only mesh data is adapted; no MakeHuman AGPL software code is imported or copied. The source base is normalized to a fictional 1.80 m body.

### Human-compatible sample geometry

| Mesh | Vertices | Triangles |
| --- | ---: | ---: |
| Anatomical body | 13,380 | 26,756 |
| Short-sleeve shirt | 2,189 | 4,087 |
| Sleeveless vest | 1,771 | 3,213 |
| Modesty shorts | 906 | 1,511 |

The new shirt/vest/shorts are authored compatible shells from that body, not the old R3 vest stretched onto an unrelated avatar. Smooth full-body normal offsets, clipped hem/neck/sleeve boundaries and shared-edge welding remove the initially observed torn hems and intersections. The active showcase selects the new shirt for the existing approved Everyday Tee / Navy and Weekend Tee / Sage associations, or the new sleeveless vest for Geometric Vest Concept / Navy. S/M remain labels for shared geometry. Original catalog fixtures, descriptions, variant admission and the independent R0–R3 diagnostic/catalog-preview paths are unchanged.

The bundled payload is `HumanShowcase/human-showcase-v1.bin`, SHA-256 `6977bd1aeba54c9f4ef82f9d7f9b8b996d030b2758e226b61dcb9fbccfe4f6e9`. The runtime validates its digest, schema, finite positions/normals, bounds, indices and spacing. Only the admitting loader can construct `HumanShowcaseMeshes`; scan/profile/replay data cannot be substituted through its initializer. Admitted CPU arrays are cached independently of disposable per-scene Metal buffers.

Reproduction uses the standard-library-only `Scripts/build_human_showcase.py` with the pinned source OBJ referenced in NOTICE; no generation or network download is needed to launch the bundled app. The converter was rerun to an external artifact and `cmp` confirmed byte-identical output.

### Interaction and honest fit-map meaning

1. Launch the same `-fitcheck-demo-internal` route or open **FitCheck Demo Showcase** from the internal hub.
2. Drag or use Left / Right; Reset restores the whole human. Show/hide the selected upper garment; modesty shorts remain visible.
3. Choose Navy Everyday Tee, Sage Weekend Tee or Navy Geometric Vest Concept in **Sample collection**.
4. Under **Inspect the human model**, choose Whole body, Head, Shoulders, Chest, Waist, Hips, Arms or Legs. The selected anatomical target stays centered while rotating. Region selection and Reset restore the default orbit; Reset does not silently change the map toggle.
5. Enable **Show sample fit map**. Red indicates closer authored shell spacing, green indicates more room. The summary reports the selected garment's authored spacing within the selected region; uncovered regions explicitly report no garment coverage.
6. Open **Synthetic surface study** for the separate S2A partial-surface A/B experiment, or **LiDAR Reconstruction Demo** for S2C replay A/B. Back restores the human inspection. Product changes start a new whole-body, map-off scene; S/M changes labels without changing geometry.

The color field is interpolated authored normal-offset data, not a fitted-garment calculation. It does not measure a person's tightness, pressure, garment dimensions or drape. No personal size recommendation is made. The map colors only the selected sample top, never the body or modesty shorts. The visible disclaimer and VoiceOver scene value preserve these limits.

Backgrounding and navigation dispose scene-owned GPU objects and restore the selected inspection using a new scene. Human updates apply orbit, appearance, region and map state together before one camera update. Largest text uses stacked region buttons in the existing scrollable controls area; rotation buttons remain a gesture alternative. The Metal studio canvas stays visible while controls scroll.

This refinement does not change scanner capture, S2A generation authorization, S2B artifact admission/storage, S2C replay authorization or the normal Release route. Human mesh data and license notices are staged only into Debug apps. No synthetic human is saved as a personal avatar.

### Preserved refinement failures and corrections

All original evidence remains outside Git under `/Users/anshbalusa/fitcheck-d2-artifacts/`:

- `first-human-smoke.png` and `human-smoke-loaded.png`: the genuine anatomical mesh rendered, but the first clothing shell exposed ragged hem edges and intersections. Full-body normal offsets, smooth spacing and welded planar clipping corrected the geometry; `human-clean-clothing-smoke.png` records the corrected actual app.
- `Targeted-1.xcresult`: the new pixel test did not compile because color classifiers were called as free functions instead of the existing `Pixels` properties. No test execution was claimed for this attempt.
- `Targeted-2.xcresult`: seven of eight focused tests passed, with zero skips. Actual human/clothing/map/region/lifecycle pixels and CPU/GPU geometry passed. The remaining assertion was the new test helper checking the hub's offscreen demo button without scrolling that hub; the helper now scrolls its actual context, retaining its reachability assertions.
- `full-verification/verification-o33ts9_6`: 365/367 Debug tests passed, zero skips. The strict new frustum regression found a real normalized edge value of `1.0026802` at a narrow viewport/extreme orbit. The human camera margin was corrected, not the test bound; `FramingFix.xcresult` passed the unchanged boundary test.
- That full run also exposed the existing largest-text R3 catalog helper losing a lazily materialized product while returning from a preview. `FullFailureEvidence/` retains the original issue description and native app hierarchy showing the catalog list rather than the expected size picker. Sample lookup now requires a hittable product or persistent top landmark, and short held drags avoid release inertia skipping large lazy cards. Product, selected-size, navigation, visibility and rendered-pixel assertions remain intact.

The first full attempt stopped at its Debug failure gate, so it supplies no iPhone SDK, Release-build or Release-isolation pass claim.

`LegacyAccessibilityFix.xcresult` subsequently passed the complete retained R3 largest-text scenario, including both vest sizes, selected-size state, rotation/reset, visibility recovery, actual pixel comparisons and return to the hub. Its summary and the focused framing summary are retained beside their result bundles; both executed the requested case with zero skips.


`full-verification/verification-i45fhgpz` then passed all 367 Debug and 17 Release-isolation tests (zero skips/expected failures), the unsigned iPhone SDK build, normal Release build and Release testability gate. Its final report failed with `NameError: human_source_hashes is not defined` in the new resource-inspection code. The correction reuses the existing strict resource-hashing helper for source assets rather than duplicating that logic; no application source, test assertion, fixture or admission gate changed. `inspection-probe/verification-r8arlgip` passes the corrected inspection against those four freshly built apps. That probe is explicitly existing-artifact inspection, not a replacement fresh full-run claim.

### Original human-demo screenshots

Evidence root: `/Users/anshbalusa/fitcheck-d2-artifacts/HumanScreenshots/`.

These are unedited PNG bytes from the fully passing `verification-i45fhgpz/DebugTests.xcresult`, exported using `xcresulttool`. The renderer/app source is unchanged by the subsequent verifier-only correction. `index.json` retains original UUID files, case identities, timestamps and SHA-256 digests. All sixteen images were visually inspected.

| Required view | File |
| --- | --- |
| Human showcase wearing Navy Everyday Tee | `01-showcase.png` |
| Actual rotated human/clothing volume | `02-rotated-clothing.png` |
| Second garment: compatible Navy sleeveless vest | `03-second-garment.png` |
| Generated synthetic partial surface A | `04-avatar-a.png` |
| Distinct generated partial surface B | `05-avatar-b.png` |
| Synthetic depth-to-3D reconstruction A | `06-lidar-result.png` |
| Clean return to the human showcase | `07-return-showcase.png` |
| Authored sample spacing map and visible disclaimer | `08-sample-fit-map.png` |
| Focused chest and waist geometry | `09-chest-focus.png`, `10-waist-focus.png` |
| Sage shirt and medium-label vest | `11-sage-tee.png`, `12-human-vest.png` |
| Distinct reconstruction B | `13-lidar-b.png` |
| Largest-accessibility human/study/reconstruction layouts | `14-largest-text-showcase.png` through `16-largest-text-lidar.png` |

Native scroll clipping at a control-panel edge is intentional; every control remains reachable by scrolling while the 3D canvas stays visible. The samples remain fictional and sizes share geometry.

### Clean final complete verification

`Scripts/verify_development.py` completed end to end in fresh mode, including corrected resource inspection:

```bash
caffeinate -disu python3 Scripts/verify_development.py \
  --simulator C07CEE05-AE0B-45B3-9E8F-09C20FCBD5B1 \
  --output-root /Users/anshbalusa/fitcheck-d2-artifacts/full-verification
```

Final report: `/Users/anshbalusa/fitcheck-d2-artifacts/full-verification/verification-e4jizse0/verification.json`. This fresh complete run includes the strengthened native-switch/readiness checks from the dark-mode audit; the earlier passing `verification-e64ci3km` report remains retained.

| Final fresh check | Result |
| --- | --- |
| Clean Debug unit tests | 336/336 |
| Full Debug UI tests | 31/31 |
| Total Debug | **367/367** |
| Unsigned generic iPhone SDK build | PASS |
| Normal Release simulator build | PASS; testability disabled |
| Release isolation unit tests | 9/9 |
| Release isolation UI tests | 8/8 |
| Total Release isolation | **17/17** |
| Actual Debug-positive / Release-negative binary markers | PASS |
| Four app bundles' resources and privacy manifests | PASS |
| Exact human payload and license/notice hashes in both Debug SDK bundles | PASS |
| Human resources absent from normal Release and Release-test apps | PASS |

Zero skips or expected failures. Verified build/test input SHA-256: `1f0a67740ffe3757de897d98348694f8d550b7e1c9a32beb7ab5483eca69a649`. Privacy remains no-tracking/no-collected-data with the original approved API reasons.

`/Users/anshbalusa/fitcheck-d2-artifacts/regression-inventory.json` compares actual final case identities to D1: all prior 358 Debug and 17 Release cases remain. Together with the retained D1→S2C identity proof, every historical 349 Debug and 15 Release case remains represented. This refinement adds nine Debug cases; no prior case was deleted, skipped or weakened. The R3 test-helper change only makes its existing gestures reach the existing assertions.

### Additional size and appearance inspection

| Simulator | Screenshot size | Appearance | Focused UI result |
| --- | --- | --- | --- |
| iPhone 17e | 1170×2532 | Light | 3/3; zero skips |
| iPhone 17 Pro Max | 1320×2868 | Dark | 3/3; zero skips |

Both exercised actual human/clothing pixels, sample-map colors, anatomical focus, product changes, lifecycle restoration, largest accessibility controls and the separate synthetic/replay scenes. The original screenshots and manifests are in `SmallLightScreenshots/` and `LargeDarkScreenshots/` beside `SmallLight.xcresult` and `LargeDarkFixed.xcresult`. Actual human framing, color contrast, map disclaimers and largest-text controls were visually inspected.

The first `LargeDark.xcresult` attempt passed two cases but exposed the new human test's generic tap hitting the labelled switch row rather than consistently toggling the native track. Its original screenshot/video evidence remains in `LargeDarkOriginalEvidence/`; the garment remained hidden, so later map/restore pixel assertions correctly failed. The test now targets the native switch track and waits for its real on/off value before retaining the same pixel assertions. Initial readiness also requires actual Navy garment pixels rather than accepting a dark background. `LargeDarkFixed.xcresult` passes all three requested cases. This is a stronger test interaction/readiness check; no app source or pixel threshold was relaxed.

### Finished human-demo recording and meeting fallback

| Actual video | Duration | Location |
| --- | ---: | --- |
| Edited meeting journey | **55.000 s** | `/Users/anshbalusa/fitcheck-d2-artifacts/human-demo-55s.mp4` |
| Unmodified Simulator source | 756.185 s | `/Users/anshbalusa/fitcheck-d2-artifacts/human-demo-original.mov` |

Both are genuine 1320×2868 iPhone 17 Pro Max Simulator capture, not generated UI or an animation substituting for the live renderer. Capture used `xcrun simctl io … recordVideo --codec=h264`; the recorder finalized successfully. `RecordedJourney.xcresult` passed both requested actual-UI journeys with zero skips. `RecordingCheckpoints/manifest.json` retains the matching real screenshot timestamps.

The meeting edit shows the human, actual rotation, sample spacing map, chest focus, Sage shirt, sleeveless vest, synthetic surface A/B, depth reconstruction A/B and clean return. AVFoundation shortened test waits/navigation and grouped the human inspection before the separate studies; timing is edited, not a real-time performance claim. No screenshot bytes were edited. `human-demo-55s.metadata.json` and `human-demo-55s-story.json` retain the exact source ranges and timing transformations.

Native AVFoundation decoded both finished files and verified duration/resolution. Every meeting segment was visually inspected using decoded frames; metadata and frames are retained in `OriginalVideoInspection/` and `MeetingVideoInspection/`.

- Original video SHA-256: `535bd278bd9d4df7195324eb745a5de52fd68382f7ebc5e1267a07e1f3954916`.
- Meeting video SHA-256: `e87edc39f5ba09a9449092d82392d81173b8e469b5dac9081d917e3b04ed786f`.

If interactive Simulator graphics are unavailable during the meeting:

```bash
open /Users/anshbalusa/fitcheck-d2-artifacts/human-demo-55s.mp4
open /Users/anshbalusa/fitcheck-d2-artifacts/HumanScreenshots/01-showcase.png
open /Users/anshbalusa/fitcheck-d2-artifacts/HumanScreenshots/08-sample-fit-map.png
```

The screenshots and video are backup evidence only. The running app still renders and rotates actual CPU/GPU mesh geometry through Metal.

### Meeting explanation and remaining limits

> FitCheck now demonstrates an anatomical 3D human with interactive sample clothing, body-area inspection and an illustrative spacing map. A separate technical path demonstrates synthetic depth-to-3D reconstruction. These are generic authored/synthetic data—not a personal scan or verified garment fit. Real-device LiDAR validation is still pending.

The human is one reviewed generic body, not a measured person or a family of personalized body shapes. S/M labels share geometry. The spacing field is not pressure, stretch, physical drape or a size recommendation. The independent original R0–R3 labs intentionally retain their diagnostic/catalog fixtures; the new anatomical human is the Friday showcase. Real personalized avatars and fit claims still require authorized body/garment data and separate hardware/physical validation. No physical phone test is claimed or requested.

### Verified current launch

From the repository root, the exact simplest command completed successfully after the final verification:

```bash
Scripts/launch_friday_demo.sh
```

It generated the Xcode project, built current unsigned Debug, installed and directly launched the human showcase on iPhone 17 FitCheck D1 / iOS 26.5 (`C07CEE05-AE0B-45B3-9E8F-09C20FCBD5B1`). No credentials or physical device were used, and no simulator was erased. The current live result was captured and inspected at `/Users/anshbalusa/fitcheck-d2-artifacts/final-running-human-demo.png`; the app is left open on the default Navy Everyday Tee human scene.

Prebuilt launches were also exercised on the main, smaller and larger simulators. An old D1 app without human assets was correctly rejected before installation. The normal Release route and independent experimental labs remain unchanged.

### Published human-avatar refinement

- Final verified implementation commit: `cd583bc024a17914ba898eb463b956c0c251c396`.
- Published branch: `feature/human-avatar-inspection-d2`.
- Draft PR: [#23 — Anatomical human and body-area inspection](https://github.com/anshbalusa-ui/itchathon/pull/23).
- Review base: `feature/friday-visual-demo-d1` at `40cee194750647657783e9eac622cc997dcb3f2e`, not `main`.

A documentation-only commit records this review identity after the implementation commit; it changes no verified build/test input. The exact delivered branch-tip SHA is recorded in `/Users/anshbalusa/fitcheck-d2-artifacts/delivery.json` and the PR head. PR #21 remains draft against `main` at S2C commit `235bee6a5cd7b334d4689ad6e09ff9f4080acb16`; PR #22 remains draft against S2C at the unchanged D1 head. No existing PR or branch was merged or modified.

