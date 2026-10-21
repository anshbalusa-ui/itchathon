# FitCheck iOS

## Internal integrated development app

Segment I0 combines the repaired #8 → #9 → #10 foundation/scanner with #11's synthetic offline catalog. Use a **Debug** build and exactly one launch argument (Xcode scheme → Run → Arguments):

| Argument | Entry |
| --- | --- |
| None | Preserved legacy home |
| `-fitcheck-avatar-internal` | Avatar metadata onboarding → guided scanner |
| `-fitcheck-catalog-internal` | Independent offline catalog |
| `-fitcheck-integrated-internal` | Internal hub: avatar/scanner, catalog, and **3D Renderer Lab** |

Conflicting internal flags fail closed to legacy home; Release ignores every internal route. No body setup, completed-avatar claim, try-on, fit estimate, purchase or live retailer data is introduced.

See the [I0 integration handoff](Docs/INTEGRATION_HANDOFF.md), [catalog foundation](Docs/CATALOG_FOUNDATION.md) and [minimum authorized retailer contract](Docs/RETAILER_CATALOG_CONTRACT.md). Segment 1B physical scanner validation remains **NOT RUN**. Legacy device statements below are historical, not new hardware results.

Segment R0 adds a genuine MetalKit 3D mannequin viewer with a separate illustrative garment. Open **3D Renderer Lab** from the Debug hub; drag or use rotation buttons, Reset View, show/hide the garment, select Navy/Stone/Sage, and Reset Appearance. It uses no camera, saved profile, personal measurements or retailer assets. These are generic procedural fixtures, not a personalized avatar, sized product, drape simulation or fit prediction. There is no standalone renderer launch flag. See [R0 architecture, compatibility and verification](Docs/RENDERER_R0_HANDOFF.md).

Segment R1 connects the offline catalog to that same Metal viewer. Select an available **Everyday Tee Navy S/M** or **Weekend Tee Sage S/M**, then **View illustrative 3D preview**. The viewer keeps the selected sample color; return to product details to change the selection. Cream has no approved material mapping and remains unsupported, as do unrelated, unavailable, unknown-availability, and discontinued variants. Sizes are catalog labels only: every supported SKU uses the same geometric shirt and generic mannequin, without a saved avatar or scan. The independent Renderer Lab and launch routes are unchanged. See [R1 association, lifecycle and fresh verification](Docs/RENDERER_R1_CATALOG_PREVIEW_HANDOFF.md).

**Your body + your favorite shirt + a candidate shirt → three signed comparisons.**

FitCheck is a native SwiftUI prototype. Choose Body or Favorite atop results to compare chest, shoulders, and length against that reference. Scores are prototype heuristics, not fit probabilities, guarantees, or validated measurement accuracy.

## Avatar-first production work

[Segment 0](Docs/AVATAR_S0_HANDOFF.md) records the protected local avatar-profile foundation in PR #8. [Segment 1A](Docs/SCANNER_S1A_HANDOFF.md) adds development-only guided LiDAR/Vision capture and an [exact Segment 1B physical-device checklist](Docs/SCANNER_S1B_DEVICE_CHECKLIST.md). Use `-fitcheck-avatar-internal`, then **Try guided capture → Start guided scan**. Capture remains provisional and requires device validation; personalized avatar rendering and fit interpretation are unavailable. The separate catalog does not use scan observations or approve avatar readiness. The legacy measurement flow remains the default, including in Release.

The [critical foundation audit](Docs/FOUNDATION_AUDIT.md) records reproduced deletion, camera-ownership, orientation-evidence, and continuity defects and their repairs. [Data/backend boundaries](Docs/DATA_ARCHITECTURE_AUDIT.md) document on-device responsibilities, future service ownership, and account/concurrent-store gaps. Passing automated tests is not physical scan validation or approval for the new customer release.

## Preserved legacy prototype flow

- Enter and save body measurements, then enter and save a named favorite shirt and candidate shirt. Measurements are edited as local drafts and stored on-device.
- Enter chest width, shoulder width, and length for each shirt. Results switch all three signed scores between Body and Favorite; negative means smaller/shorter, zero means equal to the selected reference, positive means larger/longer. There is no overall score. Body chest compares twice flat garment width against body circumference; its 0.96 m score scale maps 48 cm additional room to +50.
- Physical chest and aligned waist checks still gate size recommendations. Favorite and Body size rankings use their respective dimensions, but neither recommends a garment when measured physical checks or the favorite reference fail.
- Results show only the Body/Favorite selector and concise dimension scores; no physical-check disclaimer card or measurement-source/limits prose. This owner-approved presentation replaces the older contradictory-favorite alert.
- Enter size-chart rows from **finished-garment measurements** and compare actual sizes. Body-size recommendation charts are not interchangeable with garment measurements.

## Scanner status and limits

The guided front/side depth scan measures waist width/depth and returns an editable partial body draft with estimated waist circumference, shoulder width, and torso length. It does not measure chest circumference; manually measure and enter chest circumference before saving the body profile. The scanner still uses depth sensing for 3D spans; it does not infer circumference from a single width. An AR garment ruler is also included. Both camera flows support portrait and landscape; garment raycasts accept horizontal or vertical surfaces. Rotating a frozen body frame requires Retake, which keeps completed spans. The app has been built and installed on the connected iPhone 17 Pro Max (iOS 27.0); physical landscape capture and marker alignment still need a live check. An owner reports a physical measurement check on that phone had “pretty good accuracy” and they would trust it; no numeric tape-error or repeatability values were recorded. Treat this as qualitative anecdotal evidence, not a general accuracy claim. Garment-ruler measurement validation and timed live-demo rehearsal remain unverified. Only the connected phone was in scope; no second-phone validation was performed.

No raw body images are stored or uploaded by the app. Do not put secrets or real measurements/photos in this repository, commits, or coding-agent prompts.

## Setup and verification

Requires macOS, Xcode, and XcodeGen. `project.yml` is canonical; generate the existing project before opening it:

```bash
brew install xcodegen
xcodegen generate
open FitCheck.xcodeproj
```

The full iOS 27 simulator suite passed **46/46** on October 1, 2026 (45 unit tests and one UI test). Physical front/side scan accuracy still needs tape measurements and repeat captures. Select an installed simulator with `xcodebuild -project FitCheck.xcodeproj -scheme FitCheck -showdestinations`, then replace the simulator name below if needed:

```bash
xcodebuild -project FitCheck.xcodeproj -scheme FitCheck -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath /tmp/fitcheck-simulator-derived \
  -parallel-testing-enabled NO \
  -maximum-concurrent-test-simulator-destinations 1 \
  CODE_SIGNING_ALLOWED=NO test -quiet
```

## Repository map

```text
project.yml                 XcodeGen project and schemes
Sources/Models/             Body, garment, chart, and measurement types
Sources/Services/           Local profile store and fit/scoring engine
Sources/Views/              Manual entry, results, size chart, home flow
Sources/BodyScan/           Guided depth capture and body measurement
Sources/AR/                 Garment ruler
Tests/                      Unit tests
UITests/                    Manual-flow UI tests
Docs/                       Frontend handoff
```
