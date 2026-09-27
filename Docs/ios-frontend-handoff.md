# FitCheck iOS frontend handoff

This branch focuses on native SwiftUI presentation. It includes draft editors for body and T-shirt measurements, the My Body → My Fit → Check a Garment → Results navigation, separate signed dimension result rows, actual-garment size-chart entry and comparison, and the garment measurement confirmation screen. It also includes an app icon and accent color. No demo measurements are preloaded by these screens.

## Required app-side contracts

The frontend type-checks against the models and engine from `feat/fit-core` PR #2. The app integration owner must supply these `@MainActor ProfileStore` members without changing their meaning:

| Member | UI use |
| --- | --- |
| `bodyProfile: BodyProfile` | Display body status and initialize an edit draft. |
| `preferredGarment: GarmentProfile?` | Display My Fit and provide the favorite reference. |
| `currentGarment: GarmentProfile` | Display candidate and initialize an edit draft. |
| `currentSizeChart: GarmentSizeChart?` | Initialize chart editor and show comparison entry. |
| `lastReport: FitReport?`, `sizeComparison: SizeComparisonReport?` | Navigate to current results only. |
| `saveBody(_:) throws` | Persist validated body draft on explicit Save. |
| `saveGarment(_:role:) throws` | Persist favorite or candidate draft on explicit Save. |
| `saveSizeChart(_:) throws` | Persist only complete finished-garment size charts. |
| `evaluateCurrentGarment() throws`, `evaluateAvailableSizes() throws` | Calculate reports from current saved inputs; clear old reports on failure. |
| `deleteMeasurements()` | Delete only FitCheck's saved body, favorite, candidate, and chart. |

The store must preserve the old `fitcheck.bodyProfile` key, decode old profiles without source metadata, persist both garment roles and chart, and invalidate stale reports after any relevant save/delete. Views never bind text fields directly to saved profiles. `MeasurementField` keeps invalid text visible; unit switching uses the canonical meter value. Manual edits mark per-dimension origins and clear prior tape verification.

`GarmentScanView` receives `onSave(MeasurementKey, Double)` in meters. It treats the existing `ARMeasurementView.onMeasurement` callback as a pending value and sends it to the garment draft only after **Use Measurement**. Switching dimensions or Reset recreates the camera wrapper so an old A point cannot pair with another field. The camera/controller owner still needs to add visible A/B markers and connecting line, permission/interruption handling, and device validation.

The body camera owner should provide a real scan UI that returns an editable `BodyProfile` draft with per-dimension scan origins. `BodyProfileView` currently exposes manual entry only; a Scan action should be added when the real capture UI is connected. The camera passes six measured scalar spans in meters to `GuidedBodyScanService.scan(_:)`, which calls `BodyGeometry.circumference(width:depth:)` from PR #2. A denied or unsupported camera must leave manual entry available. No fabricated values or raw image persistence are acceptable.

## Verification and unfinished gates

- Before the core merge, Bitrig built the existing generated XcodeGen project and the body/garment draft editors successfully. After the core merge, a normal app build is blocked because the old `ProfileStore` still calls removed body-only engine APIs and lacks the store members above.
- All SwiftUI, AR wrapper, model, and engine sources type-checked together for iOS 17 using a temporary store-interface stub outside the repository. This checks view signatures, not store behavior or a runnable app.
- One connected physical phone was identified as an iPhone 17 Pro Max on iOS 27.0. Command-line installation is blocked because Xcode has no account/provisioning profile for `com.itchathon.fitcheck`. No physical depth capture, tape comparison, accuracy result, or timed rehearsal has been completed here.
- Body depth capture, real body-scan review hookup, final garment ruler controller behavior, ProfileStore persistence, report invalidation, deletion behavior, combined device build, and two 3–5 minute rehearsals remain for their owners. Simulator build alone does not close these gates.
