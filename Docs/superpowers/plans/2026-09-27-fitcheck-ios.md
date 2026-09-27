# FitCheck Guided iOS Fit Comparison Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete a real, all-live iPhone flow that measures a body, a favorite T-shirt, and a candidate, then explains physical compatibility and separate signed chest/shoulder/length Fit Scores.

**Architecture:** Evolve the existing SwiftUI app, meter-based models, UserDefaults store, pure Swift engine, and ARKit garment ruler. A helper-guided body capture controller supplies real depth-derived front/side spans to pure ellipse geometry; every capture ends in an editable draft. Favorite and candidate reuse GarmentProfile; physical checks remain separate from signed preference scores, with no averaged overall number.

**Tech Stack:** Swift 5.10 language mode, iOS 17+, SwiftUI, Foundation, Combine, ARKit, SceneKit, CoreVideo, XCTest, XcodeGen, Bitrig using the existing Xcode project. No new runtime dependency or backend.

**Spec:** [Approved product and engineering design](../specs/2026-09-27-fitcheck-ios-design.md). Also read [research and source audit](../research/2026-09-27-fitcheck-feasibility.md).

## Global Constraints

- iOS only; Android is out of scope.
- Continue the existing native SwiftUI app, Swift fit engine, ARKit ruler, local storage, and XcodeGen configuration. No restart or Bento fork.
- Body scanning remains required; manual entry is an equal input path, not a substitute for completing the scanner.
- Two builders and two physical devices: **iPhone 17 Pro and iPhone 17 Pro Max**.
- A helper may operate the rear camera. Operator-assisted measurement-location taps qualify as the required guided body scan. Fully automatic landmark extraction is not required.
- All body and both garments' required dimensions must be measured live in the full demonstration.
- **3–5 minutes** is approved for that full live demonstration. The original 60–90 seconds applies only to the pitch summary, not the complete measurement flow.
- Separate dimension Fit Scores are **−100...+100**; zero is preferred fit subject to measured body constraints. **No averaged overall score.**
- No raw-body-image persistence/upload, fabricated scan values, probability scores, or unsupported accuracy claims.
- No Android, backend/auth, retailer APIs/scraping/OCR, virtual try-on, avatar, broad garment support, or automatic landmark extraction.
- Preserve iOS 17 deployment target; Bitrig Remote's own OS requirement is separate.
- Bento is reference-only unless explicit source-reuse permission is established.

---

## 0. Execution facts and ownership

Baseline inspected: `d4313b3dda7c5fe179c9288295132458ddeb04b5`. Re-read changed files if teammates have advanced main. This plan is not a patch and its snippets are proposed implementation content, not already compiled app code.

The original 4h15m window is a scheduling constraint, not an estimate of how long this document takes to implement. Recheck actual remaining time at kickoff. Scanner feasibility and device installation are the first gates. No task may report the scanner complete merely because manual entry works.

**Owner A / integration:** Task 1, shared portion of Task 2, Tasks 3–4, Task 7, final integration.
**Owner B / scanner:** Tasks 5–6 after shared contract commit; actual device/depth probe starts during Task 1. Neither owner independently changes shared interfaces. One owner controls project.yml and merge order.

Dependency order:

```text
1 Preflight ── 2 Shared measurement/store contract
                  ├── 3 Manual product flow ── 4 Signed engine/results ── 7 Size entry
                  └── 5 Body scanner ── 6 Garment ruler polish
                                               │
                        all paths ───────────── 8 Device acceptance and release
```

Task 5's first real depth span must happen early, before finishing its UI. Workstreams integrate at small compilable commits. For local agents use separate worktrees; for Bitrig use conversation branches from the same shared-contract commit. Do not have two conversations edit ProfileStore or FitEngine simultaneously.

Shared-file merge order: A finishes Task 3 before B merges BodyProfileView hookup; A finishes Task 4's existing GarmentScanView caller cutover before B starts Task 6's rewrite. B may develop capture internals independently. A owns GarmentEntryView integrations so two branches do not rewrite its draft state concurrently.

### File map

| Path | Action | Responsibility / owner |
|---|---|---|
| `project.yml` | Modify only if scheme/signing/bootstrap requires | Canonical project, explicit test scheme / A |
| `Sources/Models/Measurements.swift` | Modify | Units, provenance, validation helpers / A |
| `Sources/Models/BodyProfile.swift` | Modify | Four required values, legacy-safe metadata / A |
| `Sources/Models/GarmentProfile.swift` | Modify | Required length, role, provenance, waist alignment / A |
| `Sources/Models/SizeChart.swift` | Modify | Actual-dimension chart kind, metadata, source / A |
| `Sources/Services/ProfileStore.swift` | Modify | Save body/favorite/candidate/chart, invalidate reports / A |
| `Sources/Services/FitEngine.swift` | Replace old semantics in place | Signed dimensions, physical status, size minimax ranking / A |
| `Sources/Views/MeasurementField.swift` | Create | Shared validated cm/inch text entry / A |
| `Sources/Views/BodyProfileView.swift` | Modify | Draft body editor + scan/review entry / A |
| `Sources/Views/GarmentEntryView.swift` | Create | One role-aware manual/capture draft form / A |
| `Sources/Views/HomeView.swift` | Modify | Body/favorite/candidate navigation and deletion / A |
| `Sources/Views/FitResultView.swift` | Modify | Signed rows, physical coverage, mixed fit / A |
| `Sources/Views/SizeChartEntryView.swift` | Create | Actual measurement rows and explicit basis / A |
| `Sources/Views/SizeComparisonView.swift` | Modify | All per-dimension scores, eligible ties/no match / A |
| `Sources/BodyScan/BodyScanService.swift` | Replace placeholder | Scalar input, ellipse estimator, validation / B after contract |
| `Sources/BodyScan/DepthMeasurement.swift` | Create | Image/depth projection and coherent sample selection / B |
| `Sources/BodyScan/BodyScanViewController.swift` | Create | ARSession, freeze/retake, endpoints, lifecycle / B |
| `Sources/BodyScan/BodyScanView.swift` | Create | SwiftUI wrapper/capture controls and draft callback / B |
| `Sources/AR/ARMeasurementViewController.swift` | Modify | Garment ruler segment/reset/tracking lifecycle / B |
| `Sources/AR/ARMeasurementView.swift` | Modify | Refresh closures + reset token bridge / B |
| `Sources/Views/GarmentScanView.swift` | Modify | Pending dimension capture; no store/engine coupling / B |
| `Sources/Support/Info.plist` | Preserve permission, modify if needed | Accurate camera use description / A |
| `Tests/FitEngineTests.swift` | Replace obsolete cases | Behavioral signed scores/physical/ranking tests / A |
| `Tests/ProfileStoreTests.swift` | Create | Legacy decode, save/relaunch, invalidation, deletion / A |
| `Tests/BodyScanTests.swift` | Create | Geometry, pixel mapping, bad samples / B |
| `README.md`, `Docs/CODEX_HANDOFF.md` | Update after runtime proof | Actual status, reproducible commands, measured limits / A |

Keep FitCheckApp/RootView unless navigation integration demonstrably needs a change. No independent FavoriteGarment or CandidateGarment field hierarchy.

## Task 1: Launch the existing app in Bitrig and on both phones

**Files:** `project.yml`, `Sources/Support/Info.plist`, README setup section only when actual setup changes.

**Interfaces:** consumes existing `FitCheck` app target; produces a known app/test scheme, actual simulator/device IDs, signed device installation, and confirmed scene-depth capability. No fake scanner API.

- [ ] **Step 1: Inspect tools, schemes, and actual devices.**

```bash
xcodebuild -version
command -v xcodegen
xcrun simctl list devices available
xcrun devicectl list devices
```

If XcodeGen is missing, install it using existing Homebrew (`brew install xcodegen`), then run `xcodegen generate`. Do not reinstall Xcode or change global developer selection without a concrete mismatch. Device OS versions and developer team come from Xcode/devicectl, not this plan.

- [ ] **Step 2: Ensure one explicit testable scheme.** If generation does not expose tests, add this block to project.yml and regenerate:

```yaml
schemes:
  FitCheck:
    build:
      targets:
        FitCheck: all
    test:
      targets:
        - FitCheckTests
```

Run `xcodebuild -list -project FitCheck.xcodeproj`. Both targets and the scheme must be listed. Keep `GENERATE_INFOPLIST_FILE: NO` and the existing plist path.

- [ ] **Step 3: Establish simulator build/test baseline once.** Copy an available simulator UDID from Step 1 into the prompted shell variable; this avoids assuming a simulator name exists.

```bash
printf 'Available simulator UDID: '
read -r SIMULATOR_UDID
export SIMULATOR_UDID
xcodebuild -project FitCheck.xcodeproj -scheme FitCheck \
  -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
  -derivedDataPath /tmp/FitCheckDerived test CODE_SIGNING_ALLOWED=NO
```

Record actual failures once and fix them; do not rerun a known failure just to confirm it. Current tests cover old behavior and are not acceptance of the new score.

- [ ] **Step 4: Open this existing project in Bitrig.** Import the repo and ask its agent to run XcodeGen, or open the locally generated FitCheck.xcodeproj. Confirm files and scheme are from this checkout. Never choose “new app” to work around project generation. Public docs establish Xcode-project support, not automatic project.yml bootstrap.

- [ ] **Step 5: Install and launch on both phones.** Select actual developer team and device in Bitrig/Xcode. Enable Developer Mode if the OS requires it. Open existing garment camera and confirm permission/session starts. Owner B checks the following runtime capability in the real app/debugger:

```swift
ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
```

Expected: true on each intended demo device; capture an actual frame with non-nil depth before claiming usable depth. Do not log images or participant measurements. If Bitrig Remote installation is unavailable due to subscription/signing, use local Xcode device deployment, not a different app.

- [ ] **Step 6: Commit only actual project/setup fixes.**

```bash
git add project.yml Sources/Support/Info.plist README.md
git commit -m "build: verify existing FitCheck project and device setup"
```

Skip commit if no tracked file changed. Do not commit generated project, certificates, provisioning profiles, or personal team credentials.

**Acceptance:** existing native app launches on both phones; simulator test command is known; scanner developer has observed real sceneDepth. Device installation failure blocks sensor work, not manual UX work.

## Task 2: Freeze shared measurement and persistence contracts

**Files:** Measurements.swift, BodyProfile.swift, GarmentProfile.swift, SizeChart.swift, ProfileStore.swift, BodyScanService.swift (input value only), BodyProfileView.swift (save call); `Tests/ProfileStoreTests.swift`.

**Interfaces produced:** the types below, plus `saveBody(_:) throws`, `saveGarment(_:role:) throws`, `saveSizeChart(_:) throws`, `deleteMeasurements()`, and injected `ProfileStore(defaults: UserDefaults = .standard)`. Existing body storage key remains `fitcheck.bodyProfile`.

- [ ] **Step 1: Add one isolated persistence regression test before changing behavior.**

```swift
@MainActor
func testFavoriteSurvivesRelaunchAndDelete() throws {
    let suite = "FitCheckTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = ProfileStore(defaults: defaults)
    let favorite = GarmentProfile(
        name: "Known tee", category: .tshirt,
        chestFlat: 0.60, waistFlat: 0, shoulderWidth: 0.50, length: 0.72
    )
    try store.saveGarment(favorite, role: .preferred)
    XCTAssertEqual(ProfileStore(defaults: defaults).preferredGarment, favorite)
    store.deleteMeasurements()
    XCTAssertNil(ProfileStore(defaults: defaults).preferredGarment)
}
```

Add a second test decoding a literal legacy body JSON with the original six keys and no metadata, then assert chest/waist/shoulder/torso retain exact values. Run only ProfileStoreTests with the Task 1 destination; initial failure should be the missing contract, not a device error.

- [ ] **Step 2: Add small shared value types in Measurements.swift.**

```swift
enum MeasurementSource: String, Codable {
    case manual, external, bodyScan, garmentScan, retailer
}

struct MeasurementOrigin: Codable, Equatable {
    var source: MeasurementSource
    var wasEdited = false
    var verifiedWithTape = false
    var observedErrorMeters: Double? = nil
}

enum LengthUnit: String, CaseIterable, Identifiable {
    case centimeters, inches
    var id: String { rawValue }
    var symbol: String { self == .centimeters ? "cm" : "in" }
    func meters(_ value: Double) -> Double {
        self == .centimeters ? value / 100 : value * 0.0254
    }
    func display(_ meters: Double) -> Double {
        self == .centimeters ? meters * 100 : meters / 0.0254
    }
}

func validLength(_ value: Double) -> Bool { value.isFinite && value > 0 }

enum ProfileValidationError: Error {
    case incompleteBody, incompleteGarment, invalidOptionalWaist
}
```

Origins are stored by `MeasurementKey.rawValue` in optional `[String: MeasurementOrigin]?` properties on BodyProfile and GarmentProfile. Optional metadata allows synthesized Codable to decode missing legacy keys; do not add required nonoptional fields with default values and assume Codable will use those defaults. `nil` origin means “Source not recorded,” not manufactured manual provenance.

Add `enum GarmentRole { case preferred, candidate }` in GarmentProfile.swift and optional `waistAtNavel: Bool? = nil`. Retain old category cases for decoding; UI/engine only admit `.tshirt` for this MVP. A waist value requires `waistAtNavel == true` to be a physical comparison.

Body isUsable checks finite positive chest, waist, shoulders, torso; hip remains optional legacy data. Garment isUsable checks chestFlat, shoulderWidth, length, and finite nonnegative waistFlat. Zero optional waist means absent at this legacy boundary. Negative optional waist is invalid, not absent.

Freeze chart metadata now so Task 4 does not depend on a type introduced only in Task 7. In SizeChart.swift add `enum ChartMeasurementBasis: String, Codable { case finishedGarment, bodyRecommendation }`; optional `measurementBasis: ChartMeasurementBasis? = nil` and `sourceNote: String? = nil` on GarmentSizeChart; optional origins/waistAtNavel on GarmentSizeVariant. Change row identity from label to `var id = UUID()`. If decoding a row without an ID, custom decoding uses `decodeIfPresent(UUID.self, forKey: .id) ?? UUID()` and preserves all dimensions; subsequent encoding stores that ID. Set the synthetic demo chart's basis to finishedGarment and source note to “Synthetic test data.” Pass metadata through asGarment immediately. New chart saves require finishedGarment basis, nonempty unique trimmed labels, and complete positive required dimensions; old invalid loaded rows remain inspectable.

- [ ] **Step 3: Add saved roles without new storage abstraction.**

Keep currentGarment name for the candidate and add `@Published private(set) var preferredGarment: GarmentProfile?`. Save candidate under `fitcheck.candidateGarment`, favorite under `fitcheck.preferredGarment`, chart under `fitcheck.sizeChart`. Body key stays unchanged. Introduce `private let defaults: UserDefaults` and decode each record independently. Corrupt records produce visible recovery state; do not silently delete valid sibling records.

Use this save ordering; do not mutate observable state before successful encoding:

```swift
func saveGarment(_ draft: GarmentProfile, role: GarmentRole) throws {
    guard draft.isUsable else { throw ProfileValidationError.incompleteGarment }
    let data = try JSONEncoder().encode(draft)
    let key = role == .preferred ? "fitcheck.preferredGarment" : "fitcheck.candidateGarment"
    defaults.set(data, forKey: key)
    if role == .preferred { preferredGarment = draft }
    else { currentGarment = draft }
    lastReport = nil
    sizeComparison = nil
}
```

Make GarmentRole Equatable to support the comparison. saveBody validates, copies draft, updates updatedAt, encodes, saves, then publishes and invalidates reports. saveSizeChart validates chart metadata/rows and invalidates sizeComparison. Deletion removes only FitCheck's four keys and clears associated in-memory values; never clears all UserDefaults.

UserDefaults does not expose a throwing disk-write completion. Surface decoding/encoding/validation failures and do not falsely claim a durable fsync acknowledgement.

- [ ] **Step 4: Freeze scanner input contract with owner B.** No raw frame enters the profile/store. Commit only BodyScanInput in this task. Agree on the following final protocol signature, but change protocol and conforming implementation together in Task 5 so the contract commit still compiles:

```swift
struct BodyScanInput {
    let chestWidth: Double
    let chestDepth: Double
    let waistWidth: Double
    let waistDepth: Double
    let shoulderWidth: Double
    let torsoLength: Double
}

protocol BodyScanning {
    func scan(_ input: BodyScanInput) throws -> BodyProfile
}
```

Owner B replaces GuidedBodyScanService's placeholder and the old protocol together in Task 5; the final implementation retains no obsolete zero-argument API. This synchronous contract processes already-captured scalars; camera work belongs to the controller. Do not introduce a new throwing stub to satisfy the new signature in the interim.

- [ ] **Step 5: Verify and commit the contract slice.** Run ProfileStoreTests, launch/relaunch once with manual values through existing UI where reachable, and confirm legacy data is not wiped. Update the body view's obsolete zero-argument save call to saveBody(store.bodyProfile) with visible error handling so this commit builds; Task 3 replaces direct bindings with drafts.

```bash
git add Sources/Models Sources/Services/ProfileStore.swift Sources/BodyScan/BodyScanService.swift Sources/Views/BodyProfileView.swift Tests/ProfileStoreTests.swift
git commit -m "feat: add preferred garment persistence and measurement provenance"
```

**Acceptance:** one shared contract commit; favorite/candidate persist; legacy body survives; invalid values are rejected; no store redesign or body image storage.

## Task 3: Complete manual-first body/favorite/candidate flow

**Files:** MeasurementField.swift, BodyProfileView.swift, GarmentEntryView.swift, HomeView.swift. Coordinate scanner sheet hookup with B rather than defining a second capture type.

**Interfaces:** consumes Task 2 store methods; produces `GarmentEntryView(role: GarmentRole)` and draft bindings consumed by scan sheets. `MeasurementField(title: String, meters: Binding<Double>, unit: LengthUnit, required: Bool, isValid: Binding<Bool>)` owns local numeric text.

- [ ] **Step 1: Add unit and invalid-input behavior checks.** In ProfileStoreTests or a small measurement test section, assert `LengthUnit.inches.meters(46) == 1.1684` within 1e-9 and `LengthUnit.centimeters.meters(116.84)` equals the same value. Check NaN, infinity, negative, and zero rejection through isUsable, not source-text searches.

- [ ] **Step 2: Implement draft-based editors with explicit save.** BodyProfileView initializes a local BodyProfile from store; garment entry initializes from selected saved role or a new GarmentProfile. Cancel dismisses without touching store. Errors are visible alerts, and navigation happens only after save succeeds.

```swift
@State private var draft = BodyProfile()
@State private var errorMessage: String?
@State private var unit: LengthUnit = .centimeters

private func saveDraft() {
    do {
        try store.saveBody(draft)
        dismiss()
    } catch {
        errorMessage = String(describing: error)
    }
}
```

Initialize once on entry, not on every view refresh after scanner dismissal. Do not reset a corrected scan draft to saved values in onAppear. Mark edited dimension origin while retaining original source; checking “Compared with tape” is separate and never automatic upon typing.

- [ ] **Step 3: Implement locale-aware text validation.** Use NumberFormatter with current locale, `.decimal`, `isLenient = false`, `generatesDecimalNumbers = true`, and full-string consumption via `getObjectValue(_:for:range:)`; reject trailing junk. NumberFormatter.number(from:) alone can accept a numeric prefix. Empty optional field maps to zero only after accepting an empty string; empty required field is invalid. Do not replace invalid text with zero or mutate saved values. Unit switching reformats from canonical meters, not previously rounded display text.

Use this parser body in MeasurementField; callers handle an intentionally empty optional field before invoking it:

```swift
private func positiveNumber(_ text: String, locale: Locale = .current) -> Double? {
    let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let formatter = NumberFormatter()
    formatter.locale = locale
    formatter.numberStyle = .decimal
    formatter.isLenient = false
    formatter.generatesDecimalNumbers = true
    var object: AnyObject?
    var range = NSRange(location: 0, length: (input as NSString).length)
    do { try formatter.getObjectValue(&object, for: input, range: &range) }
    catch { return nil }
    guard range.location == 0, range.length == (input as NSString).length,
          let number = object as? NSNumber,
          number.doubleValue.isFinite, number.doubleValue > 0 else { return nil }
    return number.doubleValue
}
```

NSRange uses UTF-16 length, not Swift character count. [Apple API contract](https://developer.apple.com/documentation/foundation/numberformatter/1412588-getobjectvalue?changes=l_6) confirms the consumed range and throwing behavior.

For valid edits, convert once with `unit.meters(value)`, check finite/positive requirements, update draft and source metadata, and clear any prior tape-verification/error-bound claim for that edited value. Show an inline “Enter a positive measurement” message on invalid required text. Use one decimal for display, but preserve the stored unrounded value until the user edits it.

- [ ] **Step 4: Build role-aware garment editor.** Use native Form fields for name, required chest/shoulder/length, optional waist, source selector (manual/external/retailer), and unit selector. Offer waist alignment toggle only when waist exists and explain navel-level correspondence. Limit category to T-shirt, explain unsupported raglan/drop-shoulder construction rather than silently applying seam comparisons. Add the real “Measure with FitCheck” sheet action with Task 6, and the body scan action with Task 5; this independent manual-flow commit has no nonfunctional capture button or speculative controller call.

Source fields are explicit for each new value. Unedited existing values retain metadata. A newly measured value becomes garmentScan, not manual. Favorite and candidate use the same form; role affects heading/save destination only.

- [ ] **Step 5: Reconcile Home navigation.** Labels: My Body, My Fit, Check a Garment. Show missing prerequisite and a route to it instead of unexplained disabled action. Allow entering a candidate early; block result evaluation until body and favorite are valid. Add destructive-confirmation deletion through store.deleteMeasurements(). Hide synthetic Load Demo Data from normal demo navigation; keep fixtures for tests with explicit synthetic names.

- [ ] **Step 6: Smoke the flow and commit.** In simulator enter body, favorite, candidate; cancel one edit; save/relaunch; switch units twice; enter comma decimal under corresponding locale; enter invalid text; delete after confirmation. Assert the same saved meter values survive and no stale report survives edits.

```bash
git add Sources/Views/MeasurementField.swift Sources/Views/BodyProfileView.swift Sources/Views/GarmentEntryView.swift Sources/Views/HomeView.swift Tests/ProfileStoreTests.swift
git commit -m "feat: add equal manual entry paths for body and garment roles"
```

**Acceptance:** camera-independent product input loop is usable; no automatic body claim exists until Task 5; canceled drafts and parse errors cannot corrupt saved records.

## Task 4: Cut over the engine and all result callers to signed dimensions

**Files:** FitEngine.swift, ProfileStore.swift, FitResultView.swift, SizeComparisonView.swift, HomeView.swift, GarmentScanView.swift callsites, FitEngineTests.swift. Do the API/model/caller cutover in one compilable commit; never retain an old body-only overload.

**Interfaces produced:**

```swift
enum FitDimension: String, CaseIterable, Identifiable {
    case chest, shoulders, length
    var id: String { rawValue }
}

enum PhysicalStatus: String, Equatable {
    case passesMeasuredChecks, needsVerification, smallerThanBody
}

struct PhysicalCheck: Identifiable, Equatable {
    let id: String // MeasurementKey.rawValue
    let bodyMeters: Double
    let candidateMeters: Double
    let easeMeters: Double
    let status: PhysicalStatus
}

struct FitDimensionResult: Identifiable, Equatable {
    var id: FitDimension { dimension }
    let dimension: FitDimension
    let preferredMeters: Double
    let candidateMeters: Double
    let deltaMeters: Double
    let signedScore: Int
    let normalizedDelta: Double // unbounded; used only for ranking
}

struct FitReport: Equatable {
    let physical: PhysicalStatus
    let referencePhysical: PhysicalStatus
    let checks: [PhysicalCheck]
    let dimensions: [FitDimensionResult]
    let preferredName: String
    let waistAssessed: Bool
    let isMixed: Bool
}

enum FitInputError: Error {
    case incompleteBody, incompleteGarment, unsupportedCategory
    case contradictoryReference, invalidChart
}

// Exact public entry points, implemented in existing FitEngine enum:
// static func evaluate(body: BodyProfile, preferred: GarmentProfile,
//                      garment: GarmentProfile) throws -> FitReport
// static func evaluateSizes(body: BodyProfile, preferred: GarmentProfile,
//                           chart: GarmentSizeChart) throws -> SizeComparisonReport
```

SizeFitResult becomes `{ id: UUID, sizeLabel: String, report: FitReport?, issue: String? }`. A row has report or issue, never neither. SizeComparisonReport contains `sizes: [SizeFitResult]` and `recommendedIDs: [UUID]`; remove closestMatch max-score behavior. Display order remains retailer order.

- [ ] **Step 1: Replace weak old score tests with concrete signed behavior.** Remove nonempty/wording/“demo 2XL wins” assertions rather than re-pinning them. Keep/strengthen physical too-small coverage under the new API.

```swift
func testOppositeDimensionErrorsRemainSeparate() throws {
    let body = BodyProfile(chestCircumference: 1.00, waistCircumference: 0.90,
                           hipCircumference: 0, shoulderWidth: 0.46, torsoLength: 0.45)
    let preferred = GarmentProfile(name: "Favorite", category: .tshirt,
        chestFlat: 0.60, waistFlat: 0, shoulderWidth: 0.50, length: 0.72)
    let candidate = GarmentProfile(name: "Candidate", category: .tshirt,
        chestFlat: 0.57, waistFlat: 0, shoulderWidth: 0.50, length: 0.78)
    let report = try FitEngine.evaluate(body: body, preferred: preferred, garment: candidate)
    XCTAssertEqual(report.dimensions.map(\.signedScore), [-50, 0, 50])
    XCTAssertTrue(report.isMixed)
    XCTAssertEqual(report.physical, .passesMeasuredChecks)
    XCTAssertFalse(report.waistAssessed)
}

func testExactPreferredDimensionsProduceZero() throws {
    let body = BodyProfile(chestCircumference: 1.00, waistCircumference: 0.90,
                           hipCircumference: 0, shoulderWidth: 0.46, torsoLength: 0.45)
    let favorite = GarmentProfile(name: "Favorite", category: .tshirt,
        chestFlat: 0.60, waistFlat: 0, shoulderWidth: 0.50, length: 0.72)
    let report = try FitEngine.evaluate(body: body, preferred: favorite, garment: favorite)
    XCTAssertEqual(report.dimensions.map(\.signedScore), [0, 0, 0])
}
```

Run FitEngineTests; missing new API/expected sign failure must be observed before implementation. Additional behavioral rows: ±0.12 m chest difference reaches ±100; exceeding endpoint saturates; nonfinite input throws; candidate circumference below body yields smallerThanBody despite exact other dimensions; favorite circumference below body throws contradictoryReference; raw scan origin without tape/error evidence yields needsVerification.

- [ ] **Step 2: Implement the signed math without an aggregate.**

```swift
private static func dimensionResult(
    _ dimension: FitDimension, preferred: Double, candidate: Double, scale: Double
) -> FitDimensionResult {
    let delta = candidate - preferred
    let normalized = delta / scale
    let score = Int(min(100.0, max(-100.0, normalized * 100.0)).rounded())
    return FitDimensionResult(dimension: dimension, preferredMeters: preferred,
        candidateMeters: candidate, deltaMeters: delta,
        signedScore: score, normalizedDelta: normalized)
}
```

Validate all input doubles and derived circumferences/deltas/normalized ratios before this function so NaN/infinity or finite-input overflow cannot reach Int conversion or ranking. Validate configuration scales as finite and positive. Define `FitScoringConfiguration` as a small value in FitEngine.swift with chestScale 0.12, shoulderScale 0.06, lengthScale 0.12, physicalReviewMargin 0.03, tieDistance 0.02. No remote config/service. Produce rows in chest/shoulders/length order; chest uses doubled widths, others direct garment dimensions.

Mixed detection ignores deltas inside 0.01 m chest and 0.005 m shoulders/length explanation deadbands. It is true only when at least one positive and one negative remaining direction exist. Never sum those deltas for a displayed score.

- [ ] **Step 3: Implement physical evidence separately.** For chest, compare candidate.chestFlat*2 with body.chestCircumference. For waist, require positive garment waistFlat and waistAtNavel == true. Body waist completeness does not authorize using an unaligned garment waist.

Negative ease => smallerThanBody. Otherwise require evidence for scan origins: a tape-verified origin contributes zero additional observed-error margin; an unverified scan contributes its finite nonnegative observedErrorMeters if explicitly set from actual calibration; no observed bound means needsVerification. Manual/external/retailer and unknown legacy provenance remain user-supplied estimates and do not acquire invented sensor bounds.

Effective review margin is `max(0.03, bodyObservedError + 2 * garmentFlatObservedError)` for circumference. Ease less than or equal to it => needsVerification; greater => passesMeasuredChecks. This is a prototype review policy, not a statistical interval. A single failing assessed dimension determines physical status, with priority smallerThanBody then needsVerification then passesMeasuredChecks.

Validate favorite chest first: if it is below body, throw contradictoryReference with actionable UI copy about remeasurement/stretch. Do not modify reference dimensions behind the user. Compute referencePhysical with the same evidence/review policy applied to the favorite's assessed measurements. Favorite close-boundary uncertainty must be visible in the result; suppress “perfect” wording even for zero scores. Display comparisons but withhold size recommendation until both candidate and reference physical evidence pass.

- [ ] **Step 4: Implement size minimax recommendation.** Evaluate each complete row using the same body/preferred API; attach an issue to invalid rows and keep them visible. Global invalid body/reference fails the whole comparison before row mapping. Use row UUID for identity, not label strings.

```swift
let eligible = sizes.filter {
    $0.report?.physical == .passesMeasuredChecks &&
    $0.report?.referencePhysical == .passesMeasuredChecks
}
let distances = eligible.compactMap { row -> (UUID, Double)? in
    guard let report = row.report else { return nil }
    let distance = report.dimensions.map { abs($0.normalizedDelta) }.max() ?? .infinity
    return (row.id, distance)
}
let best = distances.map(\.1).min()
let recommendedIDs = best.map { best in
    distances.filter { $0.1 - best <= 0.02 }.map(\.0)
} ?? []
```

Never rank on maximum signed score, averaged signed values, or clipped absolute scores. Clipping would tie mildly and extremely oversized items at +100. Duplicate/blank labels are input errors in Task 7; UUID still protects list identity during editing.

- [ ] **Step 5: Migrate store and views in the same task.** `evaluateCurrentGarment() throws` requires preferredGarment and sets lastReport only on success; `evaluateAvailableSizes() throws` requires chart/body/preferred and similarly clears stale state on failure. Clear previous report before attempting recalculation.

Remove report.score, report.band, dimension.band, ease-based legacy summary, and closestMatch references from all existing views. Home shows “View comparison,” not an aggregate badge. Garment flow leads to result after successful evaluation. Update synthetic fixture loader to include a clearly synthetic favorite or remove that user-facing loader; no hidden seeded measurements in live flow.

FitResultView renders three native rows with a shared `signedText(_ score: Int) -> String` formatter (`score > 0 ? "+\(score)" : "\(score)"`), `ProgressView` is not used as a success percentage, and a simple horizontal scale may show a zero-centered marker. Accessibility value spells “minus fifty; smaller than Favorite,” not just color.

Every row displays reference/candidate values with units and signed physical difference. Chest also shows body circumference and ease/physical status. Length uses shorter/longer language. Show mixed-fit banner only when report.isMixed. Footer states unassessed dimensions and stretch/construction limits. No “87 Fit” remnants.

- [ ] **Step 6: Verify full cutover and commit.** Run FitEngineTests; add size cases where exact eligible favorite beats a larger positive row, all candidates too small produce empty recommendedIDs, mixed ±50 does not outrank an eligible +10/+10/+10 row, and 0.01 minimax difference yields tied IDs. Exercise the manual flow with these real input values in simulator and observe −50/0/+50, then edit favorite and confirm report invalidation/recompute.

```bash
git add Sources/Services Sources/Views Sources/Models/SizeChart.swift Tests/FitEngineTests.swift
git commit -m "feat: replace aggregate fit with signed dimension comparisons"
```

**Acceptance:** no aggregate remains in active UI/API; zero is a preference target, not missing data; physical failure cannot be hidden by positive other scores; all result/size callers compile together.

## Task 5: Build and prove guided body scanning

**Files:** BodyScanService.swift, DepthMeasurement.swift, BodyScanViewController.swift, BodyScanView.swift, BodyProfileView.swift hookup; BodyScanTests.swift. B owns capture files; A handles body editor merge.

**Interfaces:** Task 2 BodyScanInput/BodyScanning. `BodyScanView(onComplete: (BodyProfile) -> Void, onCancel: () -> Void)` returns an unsaved draft. `BodyScanViewController` exposes the same callbacks. `DepthMeasurement.point(imagePoint: CGPoint, depthMeters: Float, intrinsics: simd_float3x3, imageSize: CGSize) throws -> SIMD3<Float>` consumes normalized camera-image coordinates, not viewport coordinates.

- [ ] **Step 1: Write geometry/projection regression tests.**

```swift
func testCircularAndEllipticalCircumference() throws {
    XCTAssertEqual(try GuidedBodyScanService.circumference(width: 0.4, depth: 0.4),
                   .pi * 0.4, accuracy: 1e-9)
    XCTAssertEqual(try GuidedBodyScanService.circumference(width: 0.4, depth: 0.3),
                   try GuidedBodyScanService.circumference(width: 0.3, depth: 0.4),
                   accuracy: 1e-9)
    XCTAssertThrowsError(try GuidedBodyScanService.circumference(width: .nan, depth: 0.3))
    XCTAssertThrowsError(try GuidedBodyScanService.circumference(width: 0.4, depth: 0))
}

func testBackProjectionProducesKnownSpan() throws {
    let k = simd_float3x3(columns: (
        SIMD3<Float>(1000, 0, 0), SIMD3<Float>(0, 1000, 0), SIMD3<Float>(500, 500, 1)
    ))
    let a = try DepthMeasurement.point(imagePoint: CGPoint(x: 0.4, y: 0.5),
        depthMeters: 2, intrinsics: k, imageSize: CGSize(width: 1000, height: 1000))
    let b = try DepthMeasurement.point(imagePoint: CGPoint(x: 0.6, y: 0.5),
        depthMeters: 2, intrinsics: k, imageSize: CGSize(width: 1000, height: 1000))
    XCTAssertEqual(simd_distance(a, b), 0.4, accuracy: 0.00001)
}
```

Run BodyScanTests before implementation; initial failure is missing geometry, not a silently skipped test.

- [ ] **Step 2: Replace unavailable placeholder with actual scalar geometry.** Extend BodyScanError with invalidGeometry, cameraDenied, unsupportedDepth, invalidDepth, interrupted, cancelled. Supply useful localized error descriptions; cancellation does not display a failure alert.

```swift
static func circumference(width: Double, depth: Double) throws -> Double {
    guard validLength(width), validLength(depth) else { throw BodyScanError.invalidGeometry }
    let a = width / 2, b = depth / 2
    let h = pow((a - b) / (a + b), 2)
    let result = Double.pi * (a + b) * (1 + 3 * h / (10 + sqrt(4 - 3 * h)))
    guard validLength(result) else { throw BodyScanError.invalidGeometry }
    return result
}
```

`scan(_:)` validates all six scalar spans, constructs all four required body values, marks their origins bodyScan, and leaves tape verification false/error bounds nil by default. Shoulder and torso are direct spans; no estimated hip required. Use named chest/waist calibration multipliers defaulting to 1.0, changed only with documented device evidence. No hard-coded demo person's measurements.

- [ ] **Step 3: Implement back-projection using one coordinate convention.**

```swift
static func point(imagePoint: CGPoint, depthMeters z: Float,
                  intrinsics k: simd_float3x3, imageSize: CGSize) throws -> SIMD3<Float> {
    guard imagePoint.x.isFinite, imagePoint.y.isFinite,
          (0...1).contains(imagePoint.x), (0...1).contains(imagePoint.y),
          z.isFinite, z > 0, imageSize.width > 0, imageSize.height > 0,
          k[0, 0].isFinite, k[1, 1].isFinite, k[0, 0] > 0, k[1, 1] > 0
    else { throw BodyScanError.invalidDepth }
    let u = Float(imagePoint.x * imageSize.width)
    let v = Float(imagePoint.y * imageSize.height)
    let p = SIMD3<Float>((u - k[2, 0]) * z / k[0, 0],
                        (v - k[2, 1]) * z / k[1, 1], z)
    guard p.x.isFinite, p.y.isFinite else { throw BodyScanError.invalidDepth }
    return p
}
```

This uses full camera-image pixel coordinates with full-resolution camera intrinsics; depth lookup separately uses normalized coordinates and depth dimensions. Do **not** scale intrinsics a second time in this variant. If implementing directly in depth coordinates instead, scale both focal lengths and principal point exactly once. Pairwise distances do not require a camera/world coordinate conversion.

- [ ] **Step 4: Freeze coherent RGB/depth frames and prove one span on device.** Create a small controller-owned `FrozenBodyFrame` containing retained/copied capturedImage, depthMap, confidenceMap, camera intrinsics, image resolution, and imageToView CGAffineTransform. Use exactly one ARFrame for all fields. Render the frozen image with the same display transform used for tap inversion; pause replacing its buffers until retake. At most front and side frames retained, never saved.

```swift
let normalizedView = CGPoint(x: tap.x / viewport.width, y: tap.y / viewport.height)
let normalizedImage = normalizedView.applying(frozen.imageToView.inverted())
```

`imageToView` is ARFrame.displayTransform(for: .portrait, viewportSize: viewport) captured at freeze. Reject taps outside image bounds. Do not assume raw CVPixelBuffer is portrait or ignore aspect-fill cropping. A pure transform test must round-trip portrait/cropped points through a synthetic affine transform and inverse; the actual camera overlay must be checked on device against recognizable corners.

For depth/confidence, check supported pixel formats, lock buffers read-only, use each buffer's own bytesPerRow, and unlock via defer. Neighborhood bounds clamp at image edges. Require finite positive depth and ARConfidenceLevel at least medium. No confidence map => recapture, not confidence 1.0.

Use a bounded 5×5 neighborhood. Require at least five valid samples. Sort distances; identify foreground cluster with adjacent gaps no greater than 4 cm, require a majority of valid samples in that cluster and at least five samples, then use its median. Reject ambiguity rather than averaging two surfaces. These capture thresholds are starting engineering settings; device probe may show they are unsuitable. Record any adjustments and retest both phones.

On each phone, select endpoints of a known tape span before building the whole wizard. Then try actual body boundaries. If foreground/background ambiguity prevents repeatable body spans, stop and report the observed failure; do not switch to plane raycasts or fabricate depth.

- [ ] **Step 5: Implement capture state machine and explicit endpoint guidance.**

```swift
enum BodyCaptureStage: Equatable {
    case permission, coachingFront, markingFront, coachingSide, markingSide, review
}

enum BodySpan: CaseIterable {
    case chestWidth, waistWidth, shoulders, torso, chestDepth, waistDepth
}
```

Front marks four pairs in order: chest left/right at fullest level, waist left/right at navel level, outer shoulder pair, suprasternal notch/navel torso pair. Side marks chest front/back and waist front/back at the same levels. Show measurement label and anatomical instruction; keep undo-last-point, retake-current-view, cancel, and continue. Each pair stores two accepted points within one frozen frame; once complete, save only scalar distance for BodyScanInput.

No automatic next stage after a failed sample. Retaking front clears front-derived spans; retaking side clears side-derived spans. Freeze button requires normal tracking and current depth. Cancel/background clears transient frames and unfinished points. Pause ARSession on dismissal; don't keep camera active behind review. Dispatch UI callbacks to MainActor; do not mutate SwiftUI state from an AR delegate queue.

- [ ] **Step 6: Integrate review without bypassing manual editor.** onComplete supplies BodyProfile draft to BodyProfileView. Show units, four values, origin, optional edit, and explicit tape comparison controls. Save uses Task 2 saveBody. Retry replaces the draft only with a complete accepted scan; cancellation restores previous draft. Unsupported camera/depth screen offers manual entry, but product acceptance still requires a working scanner on intended phones.

Use one camera-authorization path before ARSession.run: notDetermined requests once; authorized runs; denied/restricted show Settings/manual route. Interruption pauses and forces fresh view capture; do not combine old and relocalized session data. No AVFoundation camera session competes with ARKit.

- [ ] **Step 7: Verify and commit.** Run geometry/transform/buffer-validation tests; perform actual front+side scan on each phone; observe generated values before any edits; compare tape and repeat. Record failure counts, absolute differences, and scan duration. Verify exiting scan releases camera and reopening starts a coherent capture.

```bash
git add Sources/BodyScan Sources/Views/BodyProfileView.swift Tests/BodyScanTests.swift
git commit -m "feat: add guided front-side depth body measurement"
```

**Acceptance:** all four body values derive from real capture, not prior demo values; results editable/persistable; two-device proof; no raw image persistence; uncertainty disclosed. Geometry tests alone are insufficient.

## Task 6: Finish garment ruler as a safe reusable input

**Files:** ARMeasurementViewController.swift, ARMeasurementView.swift, GarmentScanView.swift, GarmentEntryView.swift hookup.

**Interfaces:** `GarmentScanView(onSave: (MeasurementKey, Double) -> Void)` presents selected required dimensions and returns only a confirmed measurement. `ARMeasurementView(onMeasurement: (Double) -> Void, onStatus: (String) -> Void, resetToken: UUID)` wraps the existing controller. The scanner owns no ProfileStore and performs no fit evaluation.

- [ ] **Step 1: Establish the observable regression scenario.** On a real phone select first endpoint for chest, switch to length, then tap. Expected after fix: it starts a new length point A rather than completing chest's segment. Also confirm camera callbacks do not immediately overwrite the saved garment. No permanent test that merely echoes callbacks is needed; this scenario is the device smoke.

- [ ] **Step 2: Add explicit pending state and reset.** Controller reset clears firstPoint, both marker nodes, segment line, and pending distance. Completion draws a line but retains the pending segment until Use Measurement or Reset. Prevent new A/B capture from silently overwriting the displayed pending value.

A SceneKit cylinder can connect endpoints using the midpoint, Euclidean length, and local +Y orientation:

```swift
let distance = simd_distance(start, end)
guard distance.isFinite, distance > 0 else { return }
let geometry = SCNCylinder(radius: 0.002, height: CGFloat(distance))
geometry.firstMaterial?.diffuse.contents = UIColor.systemYellow
let line = SCNNode(geometry: geometry)
line.simdPosition = (start + end) / 2
line.look(at: SCNVector3(end), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 1, 0))
sceneView.scene.rootNode.addChildNode(line)
```

For degenerate near-parallel look-at/up configurations, use simd_quatf(from: SIMD3<Float>(0,1,0), to: normalized direction) rather than allowing invalid orientation. Keep one line node, replace it on reset, and do not allocate geometry every frame for a nonrequired live preview.

- [ ] **Step 3: Fix SwiftUI bridge updates.** Coordinator stores lastResetToken. updateUIViewController refreshes both closures and invokes reset only when token changes. Field changes create a new token and clear SwiftUI pending measurement. This avoids stale field-capturing closures and prevents reset on every redraw.

- [ ] **Step 4: Add visible save/undo and camera controls.** Reticle, A/B markers, line, pending distance, dimension label, Use Measurement, Reset, Cancel. First tap/second tap wording matches actual center-reticle behavior; don't imply touch location is measured when controller raycasts center. Use Measurement calls onSave(selectedKey, meters), marks garmentScan provenance in editor, and advances to next required field or review. Previous confirmed draft dimensions survive reset of current pending segment.

Only enable successful capture while tracking normal and a raycast resolves the surface. Preserve existing plane-based measurement; restrict guidance to flat shirt on horizontal surface and do not advertise direct depth accuracy. Permission/lifecycle use the same rules as body camera. Handle interruption by clearing pending A/B and requiring new points.

- [ ] **Step 5: Device smoke and commit.** Measure a tape-known flat span, then chest/shoulders/length on both tees. Switch field mid-segment, reset after second point, cancel without save, deny permission, reopen, and background mid-segment. Confirm candidate and favorite don't overwrite each other. Record tape errors; target each required span within 1.5 cm for controlled demo, not a universal accuracy promise.

```bash
git add Sources/AR Sources/Views/GarmentScanView.swift Sources/Views/GarmentEntryView.swift
git commit -m "feat: confirm and reset garment ruler measurements safely"
```

**Acceptance:** real confirmed dimensions flow into either role, with no saved-state mutation until draft Save; existing ruler preserved and honest about its raycast method.

## Task 7: Preserve multi-size comparison with actual row entry

**Files:** SizeChart.swift, SizeChartEntryView.swift, SizeComparisonView.swift, HomeView.swift, ProfileStore.swift, FitEngineTests.swift.

**Interfaces:** `SizeChartEntryView()` edits a local chart draft and saves with store.saveSizeChart. Consume Task 2's stable row UUID, optional provenance/waist alignment, sourceNote, and ChartMeasurementBasis; do not redefine these types. `nil` basis requires user classification before scoring. Task 7 adds the entry UX and full chart-specific tests.

- [ ] **Step 1: Write chart-semantic and recommendation tests.** A bodyRecommendation chart throws invalidChart. A chart with unclassified legacy basis cannot be recommended until reviewed. A too-small row is visible but not recommended. Two identical viable rows produce two recommendedIDs. Arbitrary labels must not change dimension results.

Use the body/favorite fixtures from Task 4. Construct three real-shaped test rows: chestFlat 0.48 (too small for 1.00 m body), 0.60 (favorite), 0.66 (oversized), all shoulder 0.50/length 0.72. Assert only favorite row ID is recommended. These are explicitly synthetic test data, not a retailer claim.

- [ ] **Step 2: Implement chart basis and conversions.** UI begins with “These are finished garment measurements” confirmation and source note. Body-size ranges show a blocking explanation: obtain finished garment dimensions or measure the garment. No guessed ease conversion.

For chest input, make the interpretation explicit:

```swift
enum ChestInputBasis: String, CaseIterable {
    case flatWidth, circumference
    func flatMeters(from enteredMeters: Double) -> Double {
        self == .flatWidth ? enteredMeters : enteredMeters / 2
    }
}
```

Rows use the shared unit parser, require label/chest/shoulders/length, allow optional waist and level correspondence, and preserve original size order. Trim labels and reject blank/duplicate labels before save. Do not reorder lexical labels (2XL before L is not meaningful sizing order). Existing synthetic chart can remain only with explicit finishedGarment basis and synthetic source note.

- [ ] **Step 3: Verify metadata survives row conversion.** Task 2's asGarment passes origins and waistAtNavel as well as dimensions; source is carried by each origin and chart sourceNote is displayed separately. Confirm this path retains observed-error evidence during multi-size evaluation. Required raw dimension absence appears as an incomplete row, never a zero Fit Score. Keep malformed row issue visible if loading an older/incomplete chart; form refuses newly saving incomplete rows.

- [ ] **Step 4: Render dimension-first comparison.** Each size row shows chest/shoulder/length signed values and physical status. Highlight all recommendedIDs; zero eligible => explicit no verified match. Tie copy says similar matches, not a forced winner. Show source note and waist coverage. No overall score column, positive-number maximization, or percentage symbol.

- [ ] **Step 5: Verify and commit.** Run chart tests. Simulator smoke: enter two sizes, switch width/circumference basis, save/relaunch, compare, edit favorite, verify old comparison invalidates, recalculate. Try a body chart and observe explanation instead of results. No retailer scraping needed.

```bash
git add Sources/Models/SizeChart.swift Sources/Views/SizeChartEntryView.swift Sources/Views/SizeComparisonView.swift Sources/Views/HomeView.swift Sources/Services/ProfileStore.swift Tests/FitEngineTests.swift
git commit -m "feat: compare actual size rows using physical gates and signed dimensions"
```

**Acceptance:** existing size feature survives the new model; actual rows enter through app; body-size charts cannot generate garment scores; source/uncertainty not discarded.

## Task 8: Integrate, measure, rehearse, and freeze

**Files:** only files implicated by observed failures; README and CODEX_HANDOFF receive actual verification results/commands after proof. No speculative feature additions.

**Interfaces:** consumes integrated native app, saved records, signed report, chart, real scans; produces a tested installed commit and truthful demonstration evidence.

- [ ] **Step 1: Run the integrated test suite and simulator launch.** Use the same actual destination from Task 1:

```bash
xcodegen generate
xcodebuild -project FitCheck.xcodeproj -scheme FitCheck \
  -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
  -derivedDataPath /tmp/FitCheckDerived test CODE_SIGNING_ALLOWED=NO
xcrun simctl bootstatus "$SIMULATOR_UDID" -b
xcrun simctl install "$SIMULATOR_UDID" /tmp/FitCheckDerived/Build/Products/Debug-iphonesimulator/FitCheck.app
xcrun simctl launch "$SIMULATOR_UDID" com.itchathon.fitcheck
```

Launch command proves process launch only. Interact with manual body/favorite/candidate and observe signed results, cancel behavior, relaunch persistence, edit invalidation, and deletion. Do not claim AR tested in simulator.

- [ ] **Step 2: Install identical integrated commit on both phones.** Confirm camera permission, rear depth, interruption recovery, and airplane-mode runtime. Do not assume a scanner branch build and a separate UI branch build together constitute the finished app.

- [ ] **Step 3: Record calibration locally with consent.** For each phone, do two complete body scans and two sets of garment measurements. Tape uses the same definitions as spec. Record operator, device/OS, method, lighting, clothing, tape values, unedited scan values, absolute errors, and repeated-scan spread. Real participant data stays outside the public repo. Publish only consented aggregate error/gate outcomes and device/setup descriptions if needed.

Gates: garment spans ≤1.5 cm error; body shoulder/torso ≤2 cm; chest/waist ≤5 cm; repeated circumference spread ≤3 cm. These are proposed controlled-demo gates, not a research validation standard. Failure requires correction of acquisition/geometry or explicit scope/deadline decision. Do not improve error by silently replacing measurements with tape while calling them scan output.

Only after evidence may observedErrorMeters be populated for that measurement method/setup; keep unset otherwise. A bound observed in a tiny demo set is not population accuracy. When ease falls within actual error envelope, request tape verification. Tape verification is explicit and per dimension.

- [ ] **Step 4: Test consumer-visible boundary matrix.**

| Scenario | Required observation |
|---|---|
| Camera denied | Manual input reachable; no crash/repeated permission loop |
| No valid depth | No fabricated value; retry/manual action; scanner not accepted as complete |
| Cancel body or garment editor | Saved records unchanged |
| Body/favorite edit after report | Old report/chart highlights invalidated |
| Favorite smaller than body | Measurement conflict explained; no “perfect” score |
| Candidate chest too small, length too long | Negative chest and positive length visible; no cancellation/recommendation |
| Exact viable reference | Three zeros; body checks visible; no guarantee language |
| All sizes incompatible | No winner |
| Two equally close viable sizes | Both highlighted |
| Size chart body ranges | Blocked as wrong data basis |
| Inches/cm switching | Same stored meters; no double conversion |
| Save/relaunch/delete | Values survive until intentional deletion, then gone |
| Background/retake/field switch | No stale frame/point contamination; camera released |
| Dynamic Type/VoiceOver | Labeled values/units/actions; no color-only meaning; controls usable |
| Offline after install | Measurement/fit flow works without network |

- [ ] **Step 5: Two full timed all-live rehearsals.** Start with no saved body/favorite/candidate each time. Capture all four body values, measure three dimensions on each shirt, save/review, compute fresh report. Finish within 3–5 minutes twice. Shirts may be laid flat beforehand; measurement values may not be preloaded. Tape corrections must be visible and included in timing. Optional size comparison stage is omitted only from presentation airtime, not removed from implementation.

- [ ] **Step 6: Independent teammate review and freeze.** A reviews B's capture boundaries/lifecycle; B reviews A's score signs, body constraints, persistence, and UI. Check all named acceptance rows against actual evidence, not code presence. Record unresolved failures and do not describe them as finished. No independent automated reviewer pass was performed during planning; this execution review is still required.

- [ ] **Step 7: Update docs with observed status and commit final fixes.** Replace README's “not implemented” statements only for behavior actually verified. Record test command/results, installed commit, device OS versions, timed rehearsal, aggregate calibration limits, and known limitations. Keep raw values/images private. Remove throwaway diagnostics/capture files, keep behavioral tests, and avoid unrelated refactors.

```bash
git add Sources Tests README.md Docs/CODEX_HANDOFF.md project.yml
git commit -m "fix: integrate and verify all-live FitCheck demonstration"
```

Stage only intended changes if working in a shared checkout. Do not commit generated build artifacts or unrelated teammate edits.

**Acceptance:** one installed app completes the approved flow; exact observations support claims. A green suite, polished screen, or manually entered values alone does not satisfy scanner acceptance.

## Bitrig execution prompts

### Owner A: integration/product

```text
Read Docs/superpowers/specs/2026-09-27-fitcheck-ios-design.md and
Docs/superpowers/plans/2026-09-27-fitcheck-ios.md before changing files.
Continue this existing SwiftUI/XcodeGen app. Do not create a new project.
Own preflight, shared contracts, manual body/favorite/candidate input, local
persistence, signed dimension fit engine/results, and actual size-row entry.
Implement Tasks 1–4 and 7; coordinate Task 8 with scanner owner.
Keep iOS 17. No backend or new runtime packages. No Bento source copying.
Fit Scores are separate chest/shoulder/length numbers from -100 to +100,
zero at preferred dimensions subject to body constraints. No overall average.
Do not maximize positive scores for size recommendations. Freeze shared types
before scanner owner starts dependent work. Never substitute manual entry for
required working body scan. Run behavioral checks and interact with actual app.
Report exact commands, observed results, device blockers, and changed files.
```

### Owner B: scanner/device

```text
Read the approved specification and implementation plan in Docs/superpowers.
Work from Owner A's shared-contract commit. Own Tasks 5–6: guided body scan
and existing garment ruler polish. Do not change store/engine/shared model
contracts without agreement. First prove one real depth-derived span on both
phones, then front/side body geometry. Use helper taps, not automatic CV.
Do not use plane raycasts for body boundaries. Freeze coherent image/depth/
intrinsics/viewport transform; reject ambiguous samples. Return editable
BodyProfile draft with truthful provenance. No fixture values or raw image
storage/upload. Preserve existing plane-raycast garment ruler and add pending
save/reset and safe field changes. Test permissions, cancellation, interruption,
tape error, and repeated capture on physical devices. Simulator is insufficient.
```

### Integration/review prompt

```text
Review the integrated app against the signed-dimension specification, not the
obsolete body-only README. Check physical constraints, mixed signs, zero target,
size minimax ranking/ties, units/doubling, unknown measurement source, legacy
decode, draft cancellation, stale reports, frame/depth mapping, buffer stride,
permission/session lifecycle, and no raw-image persistence. Confirm all-live
body plus two-shirt flow on installed app, not separate branch builds.
Report observed blockers plainly; do not turn an unverified scan into a success
claim. Require two timed 3–5 minute rehearsals and actual tape comparisons.
```

## Requirement coverage and final review

| Requirement / risk | Implemented by | Evidence required |
|---|---|---|
| Existing app/Bitrig/iOS-only/no restart | 1 | Existing scheme launched on both phones |
| Body + favorite + candidate | 2–4 | Manual flow, persistence, result changes with reference |
| Required real guided body scan | 5 | Raw capture-derived values before edits, tape comparison |
| Manual parity and scan review | 3, 5 | Entry/capture converge on same draft/save |
| Chest/waist/shoulder/torso | 2, 5 | Four reviewed body values |
| Favorite/candidate chest/shoulder/length | 3, 6 | Six garment dimensions measured live |
| Source/unit/flat-vs-circumference semantics | 2–4, 7 | Conversion/provenance and basis checks |
| Signed -100...+100, 0 preferred | 4 | Symmetric tests, zero, saturation, actual UI |
| No aggregate or cancellation | 4 | -50/0/+50 mixed case remains separate |
| Physical constraints and uncertain boundaries | 4, 8 | Too-small/unverified inputs excluded from recommendation |
| Optional waist limitations | 2, 4, 7 | Alignment required, absence explicitly disclosed |
| Actual multi-size inputs preserved | 7 | Form entry, no interpolation/body-chart misuse |
| Local data/privacy/deletion | 2, 5, 8 | Relaunch, delete, capture buffer lifecycle, offline flow |
| No licensed-code assumptions | All | No copied Bento source/dependency |
| All-live 3–5 minute demo | 8 | Two timed integrated rehearsals |
| Error/lifecycle/accessibility | 3, 5, 6, 8 | Boundary matrix exercised |
| Docs match shipped reality | 8 | Only verified behavior claimed |

Self-review rules: every consumer uses the exact shared signatures; no body-only overload, report.score, report.band, or maximum-score winner survives the cutover. Every numeric measurement remains meters internally. Every score is a signed dimension comparison, never a fit probability. Every physics claim requires physical-device evidence. No app implementation, build pass, or scanner accuracy is claimed by publication of this plan.

### Planning verification performed

Before publication, a temporary native Swift script ran the proposed signed-score examples (zero, ±50, saturation, mixed signs), ellipse circle/symmetry checks, synthetic camera-intrinsics projection, full-string en_US/fr_FR number parsing with invalid-input rejection, and minimax non-cancellation. These checks passed. A separate document check passed local-link resolution, fenced-block balance, absence of unresolved marker text, eight task/acceptance sections, and required plan headers. This does not compile the proposed app or validate sensor geometry against a person. Review was inline; no independent automated reviewer was available in this planning session.
