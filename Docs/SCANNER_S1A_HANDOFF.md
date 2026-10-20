# Segment 1A — guided capture foundation

## Scope and repository findings

- Inspected current `main` (`562173f`), PR #5 (`771540b`), PR #6 (`6936d92`), PR #7 (`84312c5`), and PR #8 (`aa3e980`), plus the actual local working tree. All four PRs were open drafts; main was still the legacy measurement application. No pre-existing uncommitted tracked/untracked Codex changes were present.
- The reported Segment 0 hardening actually exists in **PR #8**, not the older PR #7. Local HEAD, the pushed branch, and PR #8 all matched `aa3e980bcd8c65f823c1ded1ba474c9dd14ece14`. Inspected protection, backup exclusion, staged replacement, deletion recovery, schema checks, and tests in source, not just the previous report.
- No app privacy manifest existed. Added required-reason declarations for scanner elapsed-time use (`35F9.1`) and existing app-local UserDefaults (`CA92.1`), declaring no tracking or off-device collection. This is not an App Store privacy/release approval.
- Fresh Segment 0 XcodeGen/build/test baseline passed **67 tests**, zero failures/skips, on Xcode 26.5 / iOS 26.5 simulator. Result: `/tmp/fitcheck-s1a-s0-baseline.xcresult`. No serious Segment 0 compilation/correctness blocker was observed.
- This branch starts from PR #8. Selectively reused the three reviewed PR #5 scanner files and its coordinator test location; did not merge its HomeView entry or other PRs. Existing manual app logic, profile data, project configuration, and avatar-profile storage stay independent.
- PR #5 originally counted valid depth across the scene, not the person; its readiness booleans had no view-orientation evidence. A temporary executable reproduced identical readiness advancing through front and side to completion. Permission completion, tracking failure, backgrounding, and stale asynchronous work also lacked a coherent attempt boundary.
- PR #6's product/production architecture is the constraint: no manual measurement UI, fake scan geometry, avatar/fit claims, persistence/upload of raw scans, or Android implementation.

## Components and ownership

| File | Responsibility |
| --- | --- |
| `ScanCaptureContracts.swift` | Plain Swift observational contract, coordinate conventions, borrowed raster access, quality and lifecycle states; no Apple camera types |
| `AvatarCaptureCoordinator.swift` | Pure generation/ticket state machine, permission decisions, view sequencing, stability and freshness policy |
| `AppleScanCamera.swift` | Main-actor ARKit rear-camera preview/session, permission adapter, interruption/orientation events, resource release |
| `AvatarFrameAnalyzer.swift` | Serial-worker Vision requests and current-frame observation assembly |
| `PersonDepthAligner.swift` | Native raster alignment, framing, on-person/regional depth coverage, calibrated provisional view cues |
| `AppleScanEvidence.swift` | Read-only, zero-copy CoreVideo buffer borrowing with scoped locks and validated storage |
| `AvatarScannerModel.swift` | Main-actor orchestration, bounded analysis dispatch, timeout, transient evidence ownership, UI state |
| `AvatarGuidedCaptureView.swift` | Explicit start introduction, camera presentation, simple instructions, unsupported/denied/retry/cancel/review screens |

All scanner code is compiled only in Debug. Entry requires the existing `-fitcheck-avatar-internal` pilot opt-in, then **Try guided capture → Start guided scan**. The default and Release root remain the legacy app. No new dependency, asset, backend, retailer adapter, geometry estimator, profile-save path, or avatar renderer was added. The camera usage description now covers guided capture as well as existing clothing tools.

## Lifecycle and concurrency invariants

1. Unsupported devices are rejected before camera permission or AR preview allocation. Denied and restricted permissions are distinct. Permission is requested only after explicit scanner start.
2. A new attempt has a new generation. Delayed/duplicate permission replies and old frame results cannot start or modify another attempt. Duplicate starts do not create another session.
3. ARSession delegates explicitly use the main queue; callbacks verify session identity and reject frames lagging the same session's latest frame. Sensor-clock timestamps are not compared to an assumed uptime epoch. UI, session ownership, and state coordination are main-actor confined; Vision and raster inspection run on one serial worker queue.
4. One physical analysis job may exist across **all** generations. Cancelling does not pretend synchronous Vision inference has stopped; no new input is queued until the old job returns. Its result is discarded if stale. No unbounded ARFrame queue or RGB copies are created.
5. Camera inputs retain immutable SDK buffers for that worker hop. The unchecked Sendable input wrapper documents this ownership rule; code never mutates the buffers. Accepted evidence retains only depth/confidence/mask, metadata, and quality—not RGB or ARFrame.
6. Cancel, disappearance, background, interruption, session failure, and explicit retry invalidate pending work and release evidence. Pausing removes/releases the ARSCNView and ARSession rather than retaining `currentFrame` on a paused session. Old session callbacks cannot resume it.
7. The initial preview-ready callback is one-shot; later appearances and foreground return cannot restart automatically. The user must retry after interruption/background. A stalled attempt times out; portrait-only capture rejects orientation changes and asks for a new attempt.
8. An inactive/background privacy cover hides the preview. Hardware OS-snapshot behavior still needs validation. An already running Vision call may retain one input until it finishes; cancellation is logical, not an immediate preemption guarantee.

## Coordinates and quality policy

- Contract version: `ScanFrameMetadata.contractVersion == 1`. Metadata is scalar/plain Swift: monotonic sensor-clock timestamp (opaque epoch), RGB/depth/mask dimensions, rotations, native-pixel pinhole intrinsics, normalized native upper-left landmarks, and within-session camera motion references. A separate local admission clock measures analysis freshness; a regression test covers different clock epochs.
- Native camera/depth raster axes are upper-left X-right/Y-down. Depth samples are Float32 metres; confidence is UInt8 (0 low, 1 medium, 2 high); mask is UInt8 probability (0…255). Row strides are explicit and padding is not data. Callers borrow pointers synchronously; pointers must not escape or be retained across async work.
- ARKit/Vision buffers never cross the core interface. A future platform adapter supplies these same calibrated observations and `ScanDepthEvidence.withPlanes`; this is not an Android implementation or a promise that Android supplies equivalent sensors.
- Native RGB goes to segmentation with EXIF `.up`, avoiding an implicit rotated mask. Pose gets the actual image rotation; Vision lower-left upright landmarks are inverted into native upper-left coordinates. No RGB rotation/copy is performed. Mask layout/aspect must match the declared full-frame sensor field of view; unexpected layouts fail closed.
- Depth/confidence share native axes but may have lower resolution. Pixel centers map through normalized full-frame coordinates to mask pixels. Calibration resolution must match the source RGB. Formats, dimensions, strides, storage lengths, principal points, finite values, and mask association are checked before reads.
- **Physical assumption requiring 1B:** native segmentation behavior and shared RGB/depth normalized field of view must hold on the actual device/SDK. A consistent aspect ratio alone cannot prove registration. Native-orientation segmentation was chosen for an unambiguous raster contract; its detection quality with portrait subjects needs device testing.
- Inspect the full mask for clipping, then sample depth only inside the person. Require distributed valid depth across upright person-relative head/torso/leg bands; background coverage cannot substitute. Exactly one detected pose is required. A missed additional person or a covert person handoff is not ruled out by pose count/context matching.
- Framing permits one visible shoulder/hip/ankle and a nose or ear; bilateral occlusion alone is not interpreted as cropping. Anatomical vertical ordering and landmark-mask association are checked.
- View cues use calibrated bilateral shoulder/hip sensor depths in upright camera axes. A front cue also requires face evidence; a side cue needs a defensible bilateral axis and no contradictory available axis/face evidence. Occluded/missing/overlapping evidence is **unverified**, not inferred from the requested phase or silhouette width. These cues are not validated orientation truth or a body surface.

### Internal provisional gates

These values are engineering rejection policies, **not accuracy claims or shopper scores**. They require 1B evaluation before acceptance for production use.

| Gate | Current policy |
| --- | --- |
| Person-mask threshold | 128 of 255 |
| Person depth coverage | at least 80% valid; at least 30 samples |
| Regional depth coverage | at least 65% in each upright band; at least 8 samples per band |
| General depth samples | finite, 0.35…5 m, confidence at least medium |
| Orientation endpoints | high confidence; distinct depth pixels |
| Provisional front/side axis cue | front at most 20°; side at least 60°; conflicting axes reject |
| Stable capture | at least 3 accepted frames over at least 0.8 s |
| Frame spacing / gap / analysis age since admission | at least 0.25 s / at most 0.8 s / at most 0.75 s |
| Whole-attempt timeout | 30 s |

Center, scale, range, and camera motion must remain stable relative to both the previous observation and the start of the stable window. A temporary executable reproduced slow cumulative drift passing a previous-frame-only check; the window-reference guard and regression now reject it. Side evidence must remain compatible with the front view's framing/range/camera context. Missing-person evidence after front invalidates the pair. Full motion thresholds are named in the pure coordinator; none is shown in the customer interface.

## Privacy and performance

- No raw photos, recordings, depth maps, masks, camera parameters, or body-derived values are written to disk, logged, uploaded, added to analytics, or committed. Synthetic fixtures only. The scanner never calls the avatar-profile repository.
- Candidate pairs remain in memory until discard/retry/background/exit. They are observational input for later research, not an avatar or a verified geometry result. The UI says **Views captured for review**, not successful body reconstruction.
- Borrowed pixel planes avoid copies; row-stride and lock handling are explicit. Analysis input is throttled, single-flight, and off the main actor. Requests are reused within an attempt, and caches are released at boundaries.
- No physical frame-rate, memory, thermal, battery, inference-latency, or usability claim is made. Two Vision requests, full-mask framing inspection, and the result-age gate require on-device profiling. Fail-closed thresholds may currently reject ordinary scans, especially heavily occluded side views.
- Logical cancellation bounds retained work, but cannot interrupt an already executing synchronous framework call. If inference consistently exceeds freshness limits, 1B must measure and revise the pipeline/policy rather than weakening rejection blindly.

## Verification record

- Xcode 26.5 (`17F42`), XcodeGen 2.46.0, iPhone 17 Pro simulator, iOS 26.5 (`23F77`), unsigned simulator builds.
- Fresh S0 baseline: 67 passed, no failures/skips.
- Initial S1A build caught an unsupported SwiftUI NavigationLink initializer and a non-Sendable input capture warning; corrected using the existing destination/Label pattern and an explicitly immutable SDK-buffer ownership wrapper.
- Production Release application build succeeded with normal production settings and `CODE_SIGNING_ALLOWED=NO`.
- A standalone executable against the actual platform-neutral policy/aligner passed unchanged-front rejection, cancelled-permission isolation, background-only-depth rejection, and valid differently sized mask/depth provisional front evidence. The core compiled without ARKit, Vision, CoreVideo, or UIKit.
- Final Debug full suite: **106 passed, zero failures/skips**, including the existing manual journey, scanner unsupported/cancel/reopen UI, permission and stale-result races, clock-epoch separation, cumulative stability, repeated appearance, and synthetic alignment/quality failures. `/tmp/fitcheck-s1a-delivery.xcresult`.
- Release isolation: **2 passed, zero failures/skips**, exercising the feature function and actual app with the opt-in flag; the Release app stayed on the legacy home. `/tmp/fitcheck-s1a-release-isolation.xcresult`. `ENABLE_TESTABILITY=YES` was used only for this verification command, not production settings.
- Binary inspection found scanner controller/model/aligner symbols and the start identifier in the Debug runtime dylib and none in the production Release executable.
- Earlier S1A suite: 101 passed, two failed. Failures were a contradictory expected front-capture event and exact floating-point equality for rotated normalized coordinates; corrected to the declared transition contract and numerical tolerance. No production quality gate was loosened to pass tests.
- A focused regression reproduced repeated preview appearance incorrectly restarting a background-interrupted attempt (`/tmp/fitcheck-s1a-appearance-before.xcresult`). Consuming the initial ready callback once corrected it; the retained regression passes in the final full suite.
- Actual introduction and unsupported/recovery surfaces were visually inspected from a temporary screenshot probe in the UI scenario. The probe was removed; synthetic/no-camera proof remains outside Git at `/tmp/fitcheck-s1a-ui-proof/`.
- Unsigned generic iPhone SDK Debug compilation succeeded, including the final clock changes. This compiles the real non-simulator capability path but does not install or validate capture on hardware. An earlier clean device build reported the existing global interface-orientation configuration warning; it was not silenced by changing legacy orientation behavior.
- `PrivacyInfo.xcprivacy` passed plist validation and was observed in Debug simulator, Release simulator, and iPhone SDK app bundles. The physical device remained unavailable; no oldest-supported-iOS runtime was installed for testing.

Representative verification commands (use an unused result-bundle path for another run):

```bash
xcodegen generate
xcodebuild -project FitCheck.xcodeproj -scheme FitCheck -configuration Debug \
  -destination 'platform=iOS Simulator,id=7F050083-C268-4F37-B730-C677F19A88EA' \
  -derivedDataPath /tmp/fitcheck-s1a-derived \
  -resultBundlePath /tmp/fitcheck-s1a-review.xcresult \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test -quiet
xcodebuild -project FitCheck.xcodeproj -scheme FitCheck -configuration Debug \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/fitcheck-s1a-device-derived CODE_SIGNING_ALLOWED=NO build -quiet
xcodebuild -project FitCheck.xcodeproj -scheme FitCheck -configuration Release \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/fitcheck-s1a-release-derived CODE_SIGNING_ALLOWED=NO build -quiet
```

Release tests used the primary simulator, `-configuration Release`, `-derivedDataPath /tmp/fitcheck-s1a-release-tests`, `-resultBundlePath /tmp/fitcheck-s1a-release-isolation.xcresult`, `-parallel-testing-enabled NO`, `-only-testing:FitCheckTests/AvatarFeatureIsolationTests`, `-only-testing:FitCheckUITests/AvatarPilotUITests`, and `ENABLE_TESTABILITY=YES CODE_SIGNING_ALLOWED=NO test -quiet`.

See [the exact Segment 1B checklist](SCANNER_S1B_DEVICE_CHECKLIST.md). No physical capture, body accuracy, real orientation reliability, or production readiness is asserted by simulator or synthetic tests.

## Segment decision

**Segment 1A: GO for review and physical-device testing only.** Both simulator and real-iPhone-SDK builds compile, deterministic and actual-simulator UI tests pass, and Release remains isolated. **Not GO for validated scanning, downstream geometry eligibility, or production release:** native mask quality/registration, orientation/occlusion behavior, subject continuity, real permission/interruption behavior, OS snapshot privacy, memory, thermal/latency, and accessibility on supported hardware remain unverified. No Segment 1B tests were executed automatically.

## References and component decision

Only existing Apple frameworks were used; no external package or model was chosen. Targeted reuse of PR #5 is appropriate for its small two-view/UI foundation, not evidence that its old capture gates were correct.

- [Apple Vision pose detection](https://developer.apple.com/documentation/vision/detecting-human-body-poses-in-images)
- [Apple person segmentation](https://developer.apple.com/documentation/vision/vngeneratepersonsegmentationrequest)
- [Apple 3D pose caveats](https://developer.apple.com/documentation/vision/identifying-3d-human-body-poses-in-images): inferred reference height is not a measured body model; no 3D pose estimator was integrated.
- [Apple required-reason API policy](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api) and [approved reasons](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons): elapsed time remains in-app; preferences are app-local.
