# Body capture retest — 11 November 2026

## Findings from the 66-second recording

- Start was gated by `trackingNormal && issue == nil`. A generic object-selection warning such as `objectNotDetected` could keep it disabled while the SDK was already in its valid `detecting` state. The regression in `BlockedStart.xcresult` failed before the repair.
- The button called “Find person” starts Apple's generic object selection, not human-body detection. `startDetecting()` requires a horizontal plane intersecting the ray through the center of the camera. Aiming at a person's torso can therefore fail before selection starts. The old instructions did not explain this requirement.
- Controls overlaid the lower camera image and hid the feet and lower box handles. The recording cannot establish that Apple's private detector itself recognized a partial human; it shows a generic selection with part of the person obscured by app controls.
- “Waiting for a depth photo” appeared before capture could produce any photos. The icon and haptics button added two unexplained affordances to that nonactionable state.

## Repairs

- SDK state now admits selection and Start commands. Quality warnings remain guidance; they do not deadlock commands. Pending operations remain guarded and time out with an actionable retry hint. Depth and reconstruction acceptance checks remain in place.
- Explicit flow: point the camera center at the floor beside the person's feet, tap **Set floor**, lift the camera and fit the selection from head to feet, then **Start scan**. **Reframe** resets a bad selection through the SDK's public `resetDetection()` API. Failed floor selection immediately explains what to do.
- The camera viewport ends above a compact control area. No app panel covers the feet or selection handles. A thin, unfilled floor target replaces the ready-state glowing reticle. Startup uses a pose symbol and essential instructions instead of a phase strip and paragraphs.
- Close expands in place into **Cancel scan**, alongside **Keep scanning**, using native glass transitions. The first tap preserves the attempt; the explicit second tap cancels it. Capture pauses while cancellation or help is open.
- Missing distance has no card, dash, fake value, or waveform button. Actual readings remain labeled by their source. Help, elapsed time, sampled-photo evidence and the persistent haptics toggle are in Scan options. Existing haptics remain active without needing a visible distance reading.
- Build requires three distinct inspected photos with a confident head landmark, both shoulders, hips and ankles inside the image, in upright anatomical order. Two completed native circles and at least 60 photos are still required. This checks visibility in photos, not complete surface reconstruction. The reader inspects each file once, drains its available backlog, and retries after the latest photo has had time to finish writing.
- Existing saved avatars, garment files, formats and app identity are preserved. No new dependency or competing camera session was introduced.

## Verification

Receipts are local under `/tmp/onyou-body-retest`; personal recordings, frames and device screenshots are not committed or uploaded.

- `BlockedStart.xcresult`: the pre-fix regression failed on all six advisory-warning combinations.
- `BodyCameraFixed.xcresult`: 19 checks passed on iPhone 17 Pro Max, iOS 27.0.1, including inline Cancel/Keep, camera exit and shirt camera restart. Inspected phone screenshots and normal/accessibility camera-chrome renders.
- `FinalPhone.xcresult`: one UI check was interrupted by a switch to another app; the tracking-loss safeguard correctly ended the attempt. This is not a successful native Start receipt.
- `ReadyPhone.xcresult`: all 20 focused phone checks passed after that interruption. It covers the full-body visibility policy, Start admission, compact UI, setup, cancel expansion, exit and shirt camera restart. The selection test exercised the recoverable floor-not-found path; it did not claim a successful person capture.
- `Delivery.xcresult`: 20 checks passed on the phone with zero failures or skips after the explicit floor-first instructions. The UI test covered floor-not-found recovery, not a completed native person capture. Optional Xcode diagnostic collection failed and the SDK emitted an internal QoS warning; test results themselves passed.
- `FinalLogic.xcresult`: 11 final focused checks passed, including the final compact progress labels and additional-detail state, without relaunching the phone.
- `bitrig test` still exits 78 for this Project.json project. Tests use a temporary external XcodeGen project. App builds and phone installation use Bitrig and the iOS 27.0 SDK.

Final phone delivery used `bitrig build -destination 'generic/platform=iOS' -scheme FitCheck` and `bitrig run` on the connected iPhone, with the existing bundle identifier and normal launch arguments. Signed build receipt: `2026-11-11T14-26-47-8c2136f0.log`. The built-in preview remains paused; the explicit device build/run delivered the app.

## Limits

The SDK permits hiding its ready-state reticle but provides no public control over the selected 3D box's brightness or line material. That selected box and the native coverage visuals retain Apple's styling. Switching to freeform capture solely to hide the box would remove the native circle-coverage contract, so this repair keeps object-centric capture.

The actual whole-person capture, finished reconstruction, selected-box correctness, recognition robustness under backlighting, and measurement accuracy still require a new human capture. The recorded scene is strongly backlit; the new UI continues to report lighting warnings. Photo visibility checks do not guarantee that a reconstructed surface includes every body part.
