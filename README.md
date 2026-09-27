# FitCheck iOS

**Your body + your favorite shirt + a candidate shirt → how the candidate compares.**

FitCheck is a native SwiftUI prototype. Body measurements set physical constraints; a saved favorite shirt sets preferred garment dimensions; a candidate is checked against both. Scores are prototype heuristics, not fit probabilities, guarantees, or validated measurement accuracy.

## Implemented flow

- Enter and save body measurements, then enter and save a named favorite shirt and candidate shirt. Measurements are edited as local drafts and stored on-device.
- Enter chest width, shoulder width, and length for each shirt. Compare candidate with favorite using separate signed chest, shoulder, and length scores: negative means smaller/shorter, zero means equal to favorite, positive means larger/longer. **There is no overall or averaged score.**
- Keep physical checks separate from preference scores: chest and, when corresponding measurements exist, waist are checked against the body. Shoulder and length scores compare garments, not body dimensions.
- Enter size-chart rows from **finished-garment measurements** and compare actual sizes. Body-size recommendation charts are not interchangeable with garment measurements.

## Scanner status and limits

The app includes an ARKit `sceneDepth` guided body scanner and an AR garment ruler. The app has been built, installed, and launched on the connected iPhone 17 Pro Max (iOS 27.0). An owner reports a physical measurement check on that phone had “pretty good accuracy” and they would trust it; no numeric tape-error or repeatability values were recorded. Treat this as qualitative anecdotal evidence, not a general accuracy claim. Garment-ruler measurement validation and timed live-demo rehearsal remain unverified. Only the connected phone was in scope; no second-phone validation was performed.

No raw body images are stored or uploaded by the app. Do not put secrets or real measurements/photos in this repository, commits, or coding-agent prompts.

## Setup and verification

Requires macOS, Xcode, and XcodeGen. `project.yml` is canonical; generate the existing project before opening it:

```bash
brew install xcodegen
xcodegen generate
open FitCheck.xcodeproj
```

Latest recorded simulator run: **42/42 tests passed, zero skipped**, on iPhone 17 / iOS 27.0 simulator. Reproduce with:

```bash
xcodebuild -project FitCheck.xcodeproj -scheme FitCheck -configuration Debug \
  -destination 'platform=iOS Simulator,id=BC1974AB-ED12-4805-8C3A-C5CF97D5616C' \
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
