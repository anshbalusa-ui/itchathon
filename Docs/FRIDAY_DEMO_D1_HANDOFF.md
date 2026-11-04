# FitCheck — Friday Demo D1

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

