What this repo does: On You captures textured body surfaces, measures flat shirts using camera depth, and draws an illustrative shirt over a saved body scan. It also keeps manual measurements and a local closet. Expected load: one person on one iPhone, with offline storage and one active capture or preview.

Audited source: GitHub integration `f84435a`, followed by the fixes in this report. Production entry, build/privacy configuration, body capture and admission, garment capture/inference, image association, try-on geometry/rendering/lifecycle, storage and their tests were traced. This was a risk-focused repository audit; the historical Debug labs were not reviewed line by line.

## Must fix — repaired

1. **Failed deletion could destroy the saved avatar** (`Sources/OnYou/AvatarScanStore.swift:66`).
   - **What this is:** The active record points to the saved USDZ model.
   - **Problem:** Deletion removed model contents before unlinking that record. Denying writes to the enclosing storage directory reproduced a remaining record pointing to a missing model.
   - **Fix:** Unlink the record first. A denied unlink preserves the existing model; failed file cleanup keeps Delete scan available, including after relaunch. A successful retry clears the stale error.
   - **If we skip it:** A failed deletion can make the user's saved scan unusable. Regression failed before the repair and passes afterward.

2. **Deleting a retaken garment could leave its current photo behind** (`Sources/Closet/ClosetStore.swift:73`).
   - **What this is:** A retake replaces a shirt's image identifier while preserving its garment identifier.
   - **Problem:** Deletion used the caller's old image identifier. Passing a pre-retake selection removed the closet entry but retained the newer photo; a filesystem regression reproduced this.
   - **Fix:** Resolve the current saved item by garment identifier before deleting its photo. Clear an old error after successful deletion.
   - **If we skip it:** A deleted garment's image can remain on the phone without a visible closet entry. Regression failed before the repair and passes afterward.

3. **Interrupted camera state could survive a new camera start** (`Sources/Closet/GarmentCaptureCamera.swift:122`, `Sources/Closet/AutomaticGarmentScanView.swift:30`).
   - **What this is:** Camera interruption disables frame admission until a new capture starts.
   - **Problem:** `needsRestart` was set on interruption but never reset. A reused controller could start AR tracking while permanently ignoring frames. Restart also depended on two asynchronous Boolean changes causing SwiftUI to destroy the controller.
   - **Fix:** Reset interruption/orientation state and cancel old analysis on an admitted camera start. Restart changes the camera view's identity, which explicitly replaces its controller; existing session-generation checks reject stale results.
   - **If we skip it:** Reappearing camera screens can remain stuck in guidance without analyzing shirts. Software ownership checks pass; physical interruption/restart still needs a user capture session.

## Should fix — repaired

4. **Users could not review the dimensions they were asked to approve** (`Sources/Closet/AddGarmentView.swift:33`, `Sources/Closet/ClosetGarmentDetailView.swift:46`).
   - **What this is:** Capture guidance asks the user to review the cutout and estimated dimensions before saving.
   - **Problem:** Both the save form and saved-shirt details omitted the numeric measurements. Users could not notice an implausible width, length or sleeve span before try-on.
   - **Fix:** Reuse one native row component in both screens. Show centimeters with locale-aware formatting, stack rows at accessibility text sizes, and expose each label/value together to VoiceOver.
   - **If we skip it:** Bad estimates can pass user review unnoticed. A largest-text UI regression verifies the saved fixture's 52 cm width, 72 cm length and 92 cm span.

5. **Recognition and cutout were tested separately from the saved-image contract** (`Tests/ClosetTests.swift`).
   - **What this is:** Capture retains landmarks tied to the exact PNG that try-on later parses.
   - **Problem:** Existing native inference checks and authored-shirt tests could both pass while a real recognized photo failed the cutout-to-pattern handoff.
   - **Fix:** Add a physical-device test using the existing licensed shirt photograph: native Core ML landmarks, Vision foreground removal, silhouette admission, exact-image evidence, saved PNG normalization and try-on pattern parsing.
   - **If we skip it:** A real image-coordinate or alpha-canvas regression could hide behind authored fixtures. This test passed on Aashutosh's iPhone 17 Pro Max running iOS 27.0.1. It is device-only because Simulator returned Vision error 9, `Could not create inference context`.

## Verification and limits

- Both storage defects were reproduced with failing tests before fixing them. Tests use temporary directories and synthetic models; no personal scans were deleted.
- The focused software run passed 51 unit cases and the existing full rendered try-on UI journey. That journey checks actual cloth pixels, rotations, visibility, reset, reopening and return to Body. The newly added dimensions UI case exposed an accessibility-value issue during its first run; it was corrected and rerun separately.
- Final changed-code run: **17 passed** (16 unit + 1 largest-text UI), 0 failures or skips. It includes denied manifest deletion, partial cleanup/relaunch/retry, stale retake selections and all three visible/accessible dimensions. Receipt: `/tmp/onyou-audit-2yqopZ/FinalChanges.xcresult`.
- Real-photo Vision/Core ML/image-contract test: **1 passed on the physical iPhone**, 0 failures or skips. This does not exercise live LiDAR or prove shirt dimensions.
- `bitrig test` exits 78 for this standard JSON project, even though its specification contains test targets. Only tests used a temporary XcodeGen project and Xcode's runner. App builds and installation use Bitrig. Temporary projects/results are outside Git at `/tmp/onyou-audit-2yqopZ`.
- Reused the existing app identity and local formats. No new dependency, cloud service, model download, fixture-success camera route or physical-fit algorithm was added.
- Removed three lines of camera timing guidance that were immediately overwritten by stabilization text. Structured timing data remains available to the existing diagnostics and benchmarks.
- Visually inspected fresh front/side/back try-on screenshots from the passing real UI journey, and the final largest-text dimension rows. These are rendered authored fixtures, not captured people. Exports: `RenderedTryOn/` and `FinalUI/` under the evidence root.
- Final signed iPhone build passed through `bitrig build -destination 'generic/platform=iOS' -scheme FitCheck`. `bitrig run` launched that exact Debug artifact on Aashutosh's connected iPhone, using the existing bundle identifier, with normal launch arguments. Build log: `2026-11-10T20-05-17-ec988ed4.log` under this project's Bitrig build logs. The separate physical image-contract receipt is `PhoneVision.xcresult` under the evidence root.
- `bitrig preview -platform iOS -scheme FitCheck` also passed compilation; its result reported the built-in preview paused. The explicit signed build/run above establishes phone delivery. No phone screenshot or real-person scan is claimed.

**Verdict:** Suitable for hands-on phone testing after these repairs. The preview is an illustration; live body reconstruction and garment-dimension accuracy still require calibrated physical captures.

**Lean:** -3 lines, -0 dependencies possible from the redundant guidance. No speculative module deletion.

**Not checked:** A real person's complete two-pass capture/reconstruction; repeatability against known measurements; real garment depth/lighting/fold variations; a physical camera interruption/restart; fabric stretch, tension, pressure or actual fit; every historical Debug lab and vendored Python training/conversion path; the full historical Debug/Release verification matrix. The SDK used was iOS 27.0.
