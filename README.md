# itchathon — FitCheck iOS

An iOS prototype for answering one question before buying clothes: **will this actually fit me?**

FitCheck creates a reusable body measurement profile, measures a garment with the camera/AR stack, then compares the two with garment-specific ease allowances to produce a dimension-by-dimension fit report and a 0–100 fit score.

## Hackathon scope

### Core demo flow
1. **Create body profile**
   - Guided scan / measurement flow
   - Chest, waist, hip, shoulder width, torso length
   - Values stored locally on device
2. **Measure garment**
   - Lay garment flat
   - AR ruler measures chest width, shoulders, waist width, length
   - Flat widths are converted to approximate circumferences where appropriate
3. **Fit check**
   - Compare garment measurements against body profile
   - Apply garment-category ease rules
   - Return fit score + explanation for each dimension
4. **Size matching**
   - When actual measurements are available for S / M / L / XL / 2XL / etc., score every size against the same body profile
   - Show the closest measurement match
   - Describe how each size would fit: e.g. fitted through chest, comfortable shoulders, relaxed waist
   - Never assume neighboring sizes scale by a fixed amount; use real brand/product measurements
5. **Results**
   - Overall score for a scanned garment
   - Per-size Fit Scores for a size chart
   - Tight / fitted / comfortable / relaxed / incompatible indicators
   - Explain *why* instead of trusting the size label alone

## Technical direction

- SwiftUI for the app shell
- ARKit for metric measurement and LiDAR-aware raycasts
- Vision / body pose as an optional assist for guided body measurement
- Local-only persistence for the hackathon prototype
- XcodeGen so the project can be generated from source
- Pure Swift fit engine so logic can be tested independently of AR

## Bento reference

We reviewed the public Bento project by cijjas because it explores a related AR measurement + fit-check workflow. This repo uses the same broad architectural lessons — separate models, AR measurement, fit logic, and SwiftUI views — but the implementation here is purpose-built for clothing fit and body profiles.

Reference: https://github.com/cijjas/bento

## Repo layout

```
Sources/
  FitCheckApp.swift
  Models/
    Measurements.swift
    BodyProfile.swift
    GarmentProfile.swift
    SizeChart.swift
  Services/
    ProfileStore.swift
    FitEngine.swift
  AR/
    ARMeasurementView.swift
    ARMeasurementViewController.swift
  BodyScan/
    BodyScanService.swift
  Views/
    RootView.swift
    HomeView.swift
    BodyProfileView.swift
    GarmentScanView.swift
    FitResultView.swift
    SizeComparisonView.swift
  Support/
    Info.plist
Tests/
  FitEngineTests.swift
Docs/
  CODEX_HANDOFF.md
project.yml
```

## Setup

Requirements:
- macOS
- Xcode 16+
- iOS 17+
- Physical iPhone recommended; LiDAR-capable device preferred for the demo

```bash
brew install xcodegen
xcodegen generate
open FitCheck.xcodeproj
```

The simulator can run the UI and fit engine, but AR measurement needs a real device.

## Hackathon MVP priorities

**Must work**
- Local body profile
- Garment AR ruler
- Fit engine
- Multi-size comparison when a real garment size chart is available
- Polished single-item and size-comparison result screens

**Nice to have**
- Automatic body landmark detection
- Depth-assisted width estimation
- Multiple garment categories
- Saved scan history

**Do not burn time on**
- Full photorealistic avatar
- Perfect circumference reconstruction
- Backend/auth
- Retail integrations before the core demo works

See `Docs/CODEX_HANDOFF.md` for the next-agent build plan.
