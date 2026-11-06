# Critical foundation audit and repair

## Scope and starting state

Reviewed actual local and remote commits, not just PR descriptions. The initially clean working tree and pushed PR #9 both pointed to `ae40f06`; PR #9 remains stacked on PR #8 (`aa3e980`). `main` remained `562173f`. PR #5 was historical context only. Product/architecture/production documents were read from planning PR #6 (`6936d92`), where those documents exist; they are not all present on the application branch.

No merge, account/backend implementation, dependency, avatar generation, geometry reconstruction, retailer integration, clothing rendering, or Android implementation was performed. The repair branch is `fix/foundation-audit-20261020`, based on PR #9.

## Engineering audit

Severity describes impact if the affected foundation is used, not an assertion that the experimental scanner is approved for production.

| Issue | Severity | Classification / evidence | Resolution |
| --- | --- | --- | --- |
| Cached file kind permits recursive deletion | High — data loss | **Confirmed.** Save a profile, delete it, recreate that destination as a directory with a marker, delete again through the same repository. Before repair no error was thrown and the marker directory was removed. | Clear the URL's cached `.isRegularFileKey` before checking current filesystem type. Shared helper protects both committed and pending paths. Existing atomic write, protection, backup, schema, and I/O semantics retained. |
| Obsolete preview dismantling detaches replacement camera | High | **Confirmed.** Attach an old controller, replace it with another driver, then invoke actual representable dismantling for the old controller. Current attempt became cancelled and the replacement stopped. | Detach requires the actual camera owner; stale teardown is ignored. Old controller still shuts down its own resources. |
| Replaced driver's delayed event interrupts current attempt | High | **Confirmed.** Retain old interruption callback, attach/start replacement, invoke old callback. Current attempt stopped. | Frame/interruption/appearance/disappearance callbacks verify attached-camera identity, using weak captures. |
| Front reused after multiple-person evidence | High | **Confirmed.** Capture front, report additional people, then submit a matching side. The old policy produced a pair. | Ambiguity invalidates attempt/evidence and requires an explicit new front. No identity verification is claimed. |
| Front reused across gaps, tracking loss, or changed camera/body context | High | **Confirmed.** Capture front, exceed existing observation/context bounds or lose tracking, then return and submit side. Context changes could also be hidden by wrong/unknown-view rejection occurring first. | Invalidate the attempt rather than merely resetting counters. Evaluate observable context before view classification; tracking loss also requires a new front. The model stops camera, drops evidence, and publishes retry on admission invalidation. Existing thresholds were not loosened. |
| Degenerate bilateral axis becomes frontal | Medium | **Confirmed.** Bilateral points differ vertically but have zero projected lateral and depth displacement; `atan2(0,0)` was interpreted as zero-angle/front evidence. | Reject the undefined projected yaw axis. No new physical tilt/yaw threshold was invented. |
| Eye points below shoulders unlock front cue | Medium | **Confirmed.** Both eye keys were sufficient even when located below shoulder level. | Front facial evidence requires both eyes above mean shoulders in upright coordinates; explicit image rotation is passed through. Rotated regression added. Ordinary side occlusion is not forced to have both eyes. |
| Native RGB/Vision rotations and raster arithmetic | High if incorrect | **No additional demonstrated mapping defect.** Existing and retained synthetic tests cover four unmirrored rotations, normalized lower-left conversion, scaled masks, padding/strides, storage length, edge clipping, confidence, and regional coverage. | Leave tested mapping and numeric quality gates intact. Aspect matching alone is not physical registration proof. |
| Pixel-center/calibration convention | Release blocker until verified | **Hardware/API uncertainty.** SDK documents pixel-unit intrinsics and depth mapping to image regions; this does not establish subpixel registration for the actual pipeline. | No guessed half-pixel correction. Require direct same-frame inspection on hardware before geometry use. |
| Ordinary side views, back/oblique views, missed people and handoff | Release blocker | **Unverified.** Bilateral occlusion can make side yaw unknowable; pose count/context is not biometric identity or proof that another person was not missed. | Preserve unknown/retry and provisional review. Device validation must establish ordinary usability and reject false views/handoffs. |
| Stale permission/results, duplicate work, timeout, attempt generations | High | Existing deterministic tests verify generation/ticket rejection and one physical analysis job across retries. No additional default-processor duplicate completion was demonstrated. | Preserve bounded worker/actor ownership; fix the independently reproduced camera-owner defects above. Synchronous Vision is not instantly preemptible. |
| Profile schema, invalid/pending state, renderer compatibility | High | Existing validation and tests distinguish missing/incomplete/invalid/unsupported data. Default renderer compatibility is false. | No schema/record rewrite. A capture candidate is not saved or promoted into usable avatar metadata. |
| Protection, atomic replacement, backup, corruption and I/O recovery | High | Code requests complete protection, excludes staged file from backup before rename, preserves invalid/unknown/corrupt committed bytes and surfaces genuine I/O errors. Existing tests retained. | Only the demonstrated deletion defect changed. Hardware keybag/lock and real backup behavior are still unverified. |
| Concurrent repository instances / future account ownership | Design risk before concurrent writes/accounts | Per-actor serialization is not a cross-instance/process transaction. Current pending filename is shared; no deterministic overlapping writer was reproduced, and capture does not save profiles. | No speculative persistence rewrite or test-only production hooks. Require a coordinated owner and account-scoped migration before those features. See architecture audit. |
| Legacy preference error handling / customer UI | Product release blocker, separate compatibility boundary | Legacy decode uses `try?`, and legacy Release UI still exposes manual measurements and fit scores. The existing manual journey was preserved and tested. | Do not silently purge data or replace the app with an unvalidated scanner. A separately reviewed consumer cutover and legacy-data policy are required; this repair is not approval for retailer release. |
| Backend and Android readiness | Design boundary, not implemented functionality | Actual services/models, dependencies, error handling, identifiers and persistence were inspected. There is no network/retailer/account client. | Keep sensor/identifying data on-device; document authorized future backend responsibilities without scaffolding. See `DATA_ARCHITECTURE_AUDIT.md`. |

## Reproduction and regression evidence

The first selected failing-before run executed eight tests against unchanged production source; **all eight failed** (`/tmp/fitcheck-audit-before.xcresult`). It reproduced directory data loss, two camera-ownership faults, three continuity scenarios, and two false-front cases.

| Regression | Covered defect |
| --- | --- |
| `AvatarProfileRepositoryTests.testDeleteDoesNotRemoveDirectoryAtPreviouslyUsedProfilePath` | Cached type and destructive directory deletion |
| `AvatarScannerLifecycleTests.testDismantlingReplacedPreviewCannotStopCurrentCamera` | Stale UI teardown |
| `AvatarScannerLifecycleTests.testReplacedCameraEventCannotInterruptCurrentAttempt` | Stale source event |
| `AvatarCaptureCoordinatorTests.testMultiplePeopleAfterFrontCannotProducePair` | Multiple-person discontinuity |
| `AvatarCaptureCoordinatorTests.testUnobservedGapAfterFrontCannotProducePair` | Observation gap |
| `AvatarCaptureCoordinatorTests.testSideMustRemainInFrontFramingAndCameraContext` | Camera/range/framing discontinuity and fresh retry |
| `PersonDepthAlignmentTests.testVerticalOnlyBilateralShoulderPointsDoNotEstablishFrontView` | Undefined projected yaw |
| `PersonDepthAlignmentTests.testEyesBelowShouldersDoNotEstablishFrontView` | Impossible face placement |
| `AvatarCaptureCoordinatorTests.testContextChangeDuringWrongOrUnknownViewCannotBeHiddenByReturning` | Context evidence must not be hidden by view rejection |
| `AvatarCaptureCoordinatorTests.testTrackingLossAfterFrontCannotProducePairAfterRecovery` | Tracking/world-context uncertainty |

After correction, the four affected suites executed **58 tests, all passed** (`/tmp/fitcheck-audit-targeted-fixed.xcresult`). The first full repaired suite executed **114 tests, all passed** (`/tmp/fitcheck-audit-full.xcresult`). An additional rotated facial-placement test preserves the upright/native distinction. No assertions were disabled or numeric quality thresholds reduced; continuity expectations now require a new attempt instead of accepting the old front after a break.

A throwaway executable against the actual repository/coordinator/aligner also passed real filesystem directory preservation and synthetic continuity/facial rejection. It printed abstract PASS categories only. Synthetic evidence is not a substitute for LiDAR hardware.

The two additional continuity regressions were then reproduced before correction: a clean coordinator-class run executed **23 tests: 21 passed, 2 failed** (`/tmp/fitcheck-audit-continuity-clean-before.xcresult`). After correction all **23 passed** (`/tmp/fitcheck-audit-continuity-after.xcresult`). The final clean full run executed **116 tests, zero failures/skips** (`/tmp/fitcheck-audit-final.xcresult`).

An initial narrow selection discovered zero tests, and an incremental class run saw the old test list. Neither was counted as evidence for the new cases; clean rebuilding exposed the failures and the final clean run includes both. The first after-fix build also caught an identifier-scope typo; it was corrected before the passing targeted suites. No test was disabled to obtain green results.

## Actual verification commands

Environment: Xcode 26.5 (`17F42`), XcodeGen 2.46.0, iPhone 17 Pro simulator / iOS 26.5 (`23F77`), x86_64 host. Real iPhone SDK builds below are unsigned compilation, not hardware execution. The existing global orientation-configuration warning remains; legacy orientations were not changed just to suppress it.

The baseline command used `/tmp/fitcheck-audit-baseline.xcresult` and `test`; it passed all **106** tests. Final verification used:

```bash
xcodegen generate
xcodebuild -project FitCheck.xcodeproj -scheme FitCheck -configuration Debug \
  -destination 'platform=iOS Simulator,id=7F050083-C268-4F37-B730-C677F19A88EA' \
  -derivedDataPath /tmp/fitcheck-audit-derived \
  -resultBundlePath /tmp/fitcheck-audit-final.xcresult \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO clean test -quiet

xcodebuild -project FitCheck.xcodeproj -scheme FitCheck -configuration Release \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/fitcheck-audit-release CODE_SIGNING_ALLOWED=NO build -quiet

xcodebuild -project FitCheck.xcodeproj -scheme FitCheck -configuration Debug \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/fitcheck-audit-device CODE_SIGNING_ALLOWED=NO build -quiet
```

All three final commands succeeded. Use an unused result path for a new run. The full suite includes unit and actual-app UI tests: default/opt-in isolation, guided introduction/unsupported/cancel/reopen, and the preserved legacy manual journey. No LiDAR hardware behavior is inferred from that UI exercise.
The final actual-app scanner smoke passed **1/1** (`/tmp/fitcheck-audit-ui-smoke.xcresult`). Introduction and unsupported/cancel/reopen surfaces were visually inspected; static/no-camera screenshots remain outside Git at `/tmp/fitcheck-audit-ui-proof/`. Temporary screenshot probes were removed.

Release isolation passed **2/2**, zero failures/skips (`/tmp/fitcheck-audit-release-final.xcresult`):

```bash
xcodebuild -project FitCheck.xcodeproj -scheme FitCheck -configuration Release \
  -destination 'platform=iOS Simulator,id=7F050083-C268-4F37-B730-C677F19A88EA' \
  -derivedDataPath /tmp/fitcheck-audit-release-tests \
  -resultBundlePath /tmp/fitcheck-audit-release-final.xcresult \
  -parallel-testing-enabled NO \
  -only-testing:FitCheckTests/AvatarFeatureIsolationTests \
  -only-testing:FitCheckUITests/AvatarPilotUITests \
  ENABLE_TESTABILITY=YES CODE_SIGNING_ALLOWED=NO test -quiet
```

Testability was enabled only on the test command, not production settings. Binary inspection found scanner controller/model/aligner symbols and the start identifier in the Debug runtime dylib and none in the production Release executable. The bundled privacy manifest passed plist validation. Fresh `xcrun devicectl list devices` still reported the physical iPhone unavailable; no hardware result is invented.



## What API/source evidence does and does not establish

- Vision body-pose coordinates are normalized with a lower-left origin. The app explicitly converts to upper-left native axes using the supplied image rotation.
- AR camera intrinsics are in image-pixel units. AR depth-map pixels correspond to regions of the captured image and contain distance values; confidence is distinct sensor evidence.
- Read-only CoreVideo locks and checked format/dimension/stride/storage arithmetic bound current pixel accesses. They do not prove that the selected pixel represents a particular person's surface.
- Full-frame native segmentation, matching aspect and scaled pixel-center mapping are explicit assumptions. They do not establish physical mask/depth registration, segmentation quality on portrait subjects, or a justified pixel-center offset.
- Front/side cues, body/motion thresholds, and same-person continuity remain provisional. No skeleton or candidate pair is a measured body model, validated geometry, or fit evidence.

References: [Apple ARDepthData](https://developer.apple.com/documentation/arkit/ardepthdata), [camera intrinsics](https://developer.apple.com/documentation/arkit/arcamera/intrinsics), [Vision body pose](https://developer.apple.com/documentation/vision/detecting-human-body-poses-in-images), [Foundation URL resource values](https://developer.apple.com/documentation/foundation/url).

## Privacy review

Source-level sink review found no scanner file writes, image/depth/mask exports, scanner-body logging, network client, scan upload, or profile-save call. Candidate buffers remain in memory and release on discard/interruption/exit after outstanding framework work finishes. No raw personal capture was used in tests or committed; fixtures are synthetic.

There is intentional pre-existing persistence: local derived avatar metadata and legacy manual-measurement preferences. This audit preserves those records; it does not claim the app stores no sensitive data at all. Avatar metadata remains protected and backup-excluded per existing code. Legacy data ownership/backup policy needs review before the consumer cutover. The required-reason manifest remains unchanged; no new service or tracking SDK was added.

OS app-switcher snapshots, hardware file protection, renderer/framework caches, memory/thermal behavior, and real network/privacy observation still need physical validation. Code inspection and simulator screenshots cannot prove those device behaviors.

## Prioritized physical blockers

No LiDAR iPhone was available at baseline; no physical test result is claimed. Use `SCANNER_S1B_DEVICE_CHECKLIST.md`, recording commit/device/iOS and PASS/FAIL/NOT RUN without body imagery or personal measurements.

1. **Registration before geometry:** same-frame RGB, native segmentation, transformed landmarks, depth/confidence and intrinsics on real hardware; inspect mapping in memory, including resolution changes and image edges. Do not infer registration from aspect ratio.
2. **Usable and safe orientation:** ordinary left/right side views under bilateral occlusion; repeated front, oblique/back, partial body and missed/additional-person rejection. Unknown must remain retry, not fake success.
3. **Continuity:** camera/range/framing changes during turn or uncertain views, tracking loss, gaps, person exit/handoff, interruptions and overlapping attempts. No old front may be silently reused after a detected break.
4. **Lifecycle/resource privacy:** delayed permission, cancel/dismiss/background/lock, retry after timeout, camera indicator/session cleanup, snapshot cover, retained buffers, and Instruments memory/latency/thermal checks.
5. **Durable data and compatibility:** protection while locked, unlock/retry, backup exclusion and deletion with synthetic records; oldest-supported-iOS runtime and VoiceOver/large text.

## Next-segment decision

**GO for physical scanner testing only, after review.** Not GO for avatar geometry research or customer release. Passing simulator tests cannot establish scan accuracy. No new segment, physical experiment, or merge is automatically authorized by this report.
