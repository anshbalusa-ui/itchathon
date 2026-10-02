# FitCheck iOS

**Your body + your favorite shirt + a candidate shirt → three signed comparisons.**

FitCheck is a native SwiftUI prototype. Choose Body or Favorite atop results to compare chest, shoulders, and length against that reference. Scores are prototype heuristics, not fit probabilities, guarantees, or validated measurement accuracy.

## Implemented flow

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
