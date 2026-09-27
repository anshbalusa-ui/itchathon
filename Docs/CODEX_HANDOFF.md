# Codex handoff — FitCheck

## Product intent

Build a polished iOS hackathon demo that helps people who are underserved by inconsistent apparel sizing determine whether an item is likely to fit before buying it.

Core value:

**scan yourself once → measure/ingest a garment → get an explainable fit result**

## Current repo state

The repo already contains:
- XcodeGen project definition
- SwiftUI navigation shell
- local body profile persistence
- garment profile model
- pure-Swift fit engine
- LiDAR-aware ARKit two-point ruler for flat garment measurements
- body scanning service boundary
- fit-result UI
- basic tests

Build on this structure. Do not restart it.

## Immediate tasks

### 1. Compile first

Run:

```bash
xcodegen generate
xcodebuild -project FitCheck.xcodeproj -scheme FitCheck -sdk iphonesimulator build
```

Fix compiler errors before redesigning the app. Then test AR on a physical iPhone.

### 2. Polish the demo flow

```
Landing
  ↓
Create My Fit
  ↓
guided body profile
  ↓
Measure Clothing
  ↓
Chest → Shoulders → Waist → Length
  ↓
Analyze Fit
  ↓
Fit Score + explanation
```

Use a modern Apple-native visual system: large type, neutral surfaces, strong hierarchy, and minimal clutter.

### 3. Improve garment measurement

The current AR ruler is intentionally small.

Add:
- visible A/B markers
- line between points
- live distance preview
- explicit save action for each requested dimension
- reset / undo
- LiDAR availability indicator
- confidence/coaching state
- haptic feedback
- measurement summary before analysis

Flat garment chest and waist are widths. The model doubles them before circumference comparison.

### 4. Body scan implementation

Do not start by promising perfect automatic circumference.

Recommended build order:

**Phase A — demo reliability**
- manual profile entry/correction
- guided posture screen
- camera-assisted shoulder width if practical

**Phase B — camera/depth assist**
- Vision human-body pose landmarks
- ARKit scene depth
- map shoulder landmarks into metric world coordinates
- estimate visible torso widths

**Phase C — circumference experiment**
- guided front + side captures OR an elliptical approximation
- attach confidence
- keep manual correction available

Keep scanning behind the existing `BodyScanning` protocol.

### 5. Fit engine

Current fit allowances are hackathon heuristics. Improve by:
- moving garment-category allowance ranges into config
- adding user-readable reason strings
- testing weighting
- optionally adding material/stretch metadata
- never presenting the score as a tailoring guarantee

For this hackathon, deterministic and explainable beats ML.

## Bento reference

Reference:
https://github.com/cijjas/bento

Useful ideas:
- XcodeGen-based iOS structure
- UIKit/ARKit measurement controller wrapped in SwiftUI
- measurement/profile separation
- pure fit logic
- LiDAR enhancement with graceful fallback

Treat Bento as architectural reference, not source to copy verbatim.

## Demo script target

1. Create/load body profile.
2. Lay tee flat.
3. Measure chest.
4. Measure shoulders.
5. Measure waist/length if time permits.
6. Tap Check Fit.
7. Show a large Fit Score.
8. Explain which dimensions are comfortable, fitted, tight, or relaxed.

## Long-term product

The long-term version should not require users to physically scan every garment.

Potential garment inputs:
- retailer-provided measurements
- reseller measurement cards
- structured size charts
- marketplace integrations

The saved body profile becomes reusable across products.

## Non-goals

Do not prioritize:
- auth/backend
- social feed
- photorealistic avatar
- virtual try-on rendering
- broad retailer scraping
- generative AI unless it directly improves the fit explanation

The demo should feel fast, clear, and believable.
