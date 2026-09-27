# FitCheck iOS frontend handoff

This branch focuses on native SwiftUI presentation. It includes draft editors for body and T-shirt measurements, the My Body → My Fit → Check a Garment → Results navigation, separate signed dimension result rows, actual-garment size-chart entry and comparison, and the garment measurement confirmation screen. It also includes an app icon and accent color. No demo measurements are preloaded by these screens.

## App-side contracts

The frontend uses the models and engine from `feat/fit-core` PR #2. `ProfileStore` now supplies these `@MainActor` members:

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

The store preserves the old `fitcheck.bodyProfile` key, decodes old profiles without source metadata, persists both garment roles and chart, and invalidates stale reports after relevant save/delete. Views never bind text fields directly to saved profiles. `MeasurementField` keeps invalid text visible; unit switching uses the canonical meter value. Manual edits mark per-dimension origins and clear prior tape verification.

`GarmentScanView` receives `onSave(MeasurementKey, Double)` in meters. It treats the existing `ARMeasurementView.onMeasurement` callback as a pending value and sends it to the garment draft only after **Use Measurement**. Switching dimensions or Reset recreates the camera wrapper so an old A point cannot pair with another field. The camera/controller owner still needs to add visible A/B markers and connecting line, permission/interruption handling, and device validation.

The body camera owner should provide a real scan UI that returns an editable `BodyProfile` draft with per-dimension scan origins. `BodyProfileView` currently exposes manual entry only; a Scan action should be added when the real capture UI is connected. The camera passes six measured scalar spans in meters to `GuidedBodyScanService.scan(_:)`, which calls `BodyGeometry.circumference(width:depth:)` from PR #2. A denied or unsupported camera must leave manual entry available. No fabricated values or raw image persistence are acceptable.

## Verification and unfinished gates

- The old `ProfileStore` build blocker is resolved. Bitrig build and one local iPhone 17 simulator build/install/launch succeeded. Home and manual entry screens were visually inspected. 31 unit tests passed, including `ProfileStoreTests`. One UI test passed, exercising body → favorite → candidate → results, relaunch persistence, cancel-without-saving, and deletion.
- Bitrig's built-in simulator API returned no registered simulators in this workspace, so interactive tests use the single Xcode iPhone 17 simulator. No other simulator was booted.
- One connected physical phone was identified as an iPhone 17 Pro Max on iOS 27.0. Command-line installation is blocked because Xcode has no account/provisioning profile for `com.itchathon.fitcheck`. No physical depth capture, tape comparison, accuracy result, or timed rehearsal has been completed here.
- Body depth capture, real body-scan review hookup, final garment ruler controller behavior, physical-device build, tape accuracy comparison, and two 3–5 minute rehearsals remain open. Simulator build alone does not close these gates.
