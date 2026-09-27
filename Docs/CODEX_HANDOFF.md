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
- garment size-chart models
- signed per-size fit scoring (-100...+100) and natural-language fit descriptions
- size-comparison UI with a closest measurement match
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
Single garment Fit Score
  ↓
If size chart exists: compare S / M / L / XL / 2XL / etc.
  ↓
Per-size scores + fit descriptions
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

### 5. Multi-size matching

This is a core product feature, not a nice-to-have.

When a retailer/seller provides actual measurements for each size, evaluate every available size against the saved body profile using `FitEngine.evaluateSizes`.

The Fit Score scale is a core product invariant:

- **-100** = much too small
- **0** = ideal target fit
- **+100** = much too large
- the closer a score is to **0**, the closer the size is to the target fit
- negative values mean undersized/tighter than ideal
- positive values mean oversized/looser than ideal

The result should answer both:
- **Which available size is the closest measurement match?**
- **How would each available size fit?**

Example presentation:

```
XL — -68 Fit
Very snug through chest
Too small at shoulders
Fitted through waist

2XL — -12 Fit
Near ideal through chest
Near ideal at shoulders
Near ideal through waist

3XL — +42 Fit
Relaxed through chest
Relaxed at shoulders
Relaxed through waist
```

Important: never infer a complete size chart by adding a fixed number of centimeters to one scanned size. Apparel grading differs across brands and products. Multi-size comparison must use actual measurements from a retailer size chart, seller-provided data, or individually measured sizes.

The size label itself is only an identifier. FitCheck should base the score on measurements.

Future input paths can include:
- retailer product APIs
- structured size-chart entry
- OCR/extraction from a retailer size chart
- seller-provided garment measurements

### 6. Fit engine

Current fit allowances are hackathon heuristics. Preserve the signed scoring contract while improving them:

`-100 → too small | 0 → ideal | +100 → too large`

Improve by:
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
9. Show an available size chart and compare every size.
10. Highlight the size whose signed Fit Score is closest to 0 while still showing how adjacent sizes would fit.

## Long-term product

The long-term version should not require users to physically scan every garment.

Potential garment inputs:
- retailer-provided measurements
- reseller measurement cards
- structured size charts
- marketplace integrations

The saved body profile becomes reusable across products.

The strongest product experience is:

`saved body profile + product-specific size chart → personalized fit score for every available size`

A user should be able to see that one brand's XL may fit differently from another brand's XL because the comparison is based on actual garment measurements, not the label.

## Non-goals

Do not prioritize:
- auth/backend
- social feed
- photorealistic avatar
- virtual try-on rendering
- broad retailer scraping
- generative AI unless it directly improves the fit explanation

The demo should feel fast, clear, and believable.
