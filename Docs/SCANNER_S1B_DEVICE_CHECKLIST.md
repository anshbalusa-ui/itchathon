# Segment 1B — physical LiDAR validation checklist

**Not executed during Segment 1A or the foundation repair audit.** A simulator, generic-device build, synthetic raster, plausible skeleton, or two captured views does not establish real scan validity. Do not proceed into geometry/avatar generation as part of these checks. Start with the priorities and known limitations in [the foundation audit](FOUNDATION_AUDIT.md).

## Setup and recording rules

- [ ] Use the reviewed foundation-repair commit on an actual LiDAR iPhone Pro. Record commit, device model, iOS build, Xcode/SDK, build configuration, and test date. Also use a physical unsupported iPhone if available; record missing hardware explicitly.
- [ ] Select a signing team locally in Xcode without committing account identifiers, provisioning profiles, or credentials. Build/install a Debug app; add `-fitcheck-avatar-internal` to Run arguments. Use **Try guided capture → Start guided scan**.
- [ ] Obtain informed consent from a clothed volunteer. Use a helper or stable mount with the rear camera facing the subject. No tape, measurement entry, manual markers, or body-size targets. Stop if uncomfortable. Do not collect identity or personal dimensions in the test record.
- [ ] Disable screenshots/screen recording, frame export, network payload capture containing images, sensitive console logging, and automatic attachment of body imagery to bug reports. Use only transient in-memory inspection. Keep consent and any sensitive research notes outside Git and GitHub.
- [ ] Begin with ordinary even indoor lighting, unobstructed head-to-feet framing, and portrait phone orientation. Then vary one condition at a time. Do not relax thresholds to obtain a demonstration pass.
- [ ] Check the known baseline first: launch without the flag and run the existing manual flow; Release with the flag must still open the legacy home. Record **PASS / FAIL / NOT RUN**, never assume unrun cases passed.

## Required scenarios

For every row record: case ID, observed user state sequence, whether a front/side candidate was emitted, expected-vs-observed outcome, recovery result, and issue reference. Logs may contain abstract state/rejection categories and aggregate timings only—not frames, masks, intrinsics, landmark positions, depths, or body measurements.

| ID | Exact action | Required observable result |
| --- | --- | --- |
| P01 | Reset camera authorization. Open the development introduction, then leave without starting. | No permission prompt, camera indicator, session, or scan result. |
| P02 | Start on supported hardware with authorization undetermined; grant permission. | One prompt; one session starts only while the scanner remains visible; initial front guidance. No second session from duplicate view appearances. |
| P03 | Deny permission. Retry, then grant in Settings and return. | Clear denied state, no session while denied; no automatic foreground restart; explicit retry re-reads authorization and starts cleanly. |
| P04 | Test restricted camera access, using device restrictions where permitted. | Restricted state, no capture and no false claim that a scan completed. Remove restrictions afterward. |
| P05 | Start on a non-LiDAR/unsupported physical iPhone; repeat in simulator. | Unsupported explanation before permission or preview allocation; cancel returns safely. No manual-measurement fallback in this journey. |
| P06 | While a permission request is pending, dismiss/cancel or background the scanner before resolving it; grant afterward. Repeat with deny. | No delayed startup, camera indicator, UI completion, or retained pair after cancellation/background. A new explicit attempt is independent. |
| F01 | Point at an empty room with excellent scene depth. | Missing-person/reposition guidance; no view accepted. Valid background depth never substitutes for person depth. |
| F02 | Introduce another person, including one at an edge or partly behind the subject. | Multiple/ambiguous person evidence must not be accepted as one valid subject. A missed extra person is a blocking defect, not proof of identity. |
| F03 | Crop head, either foot, shoulders, then move so segmentation touches each image edge. | Appropriate framing/reposition instruction; no cropped candidate. Restore complete framing and verify recovery. |
| F04 | Place subject small/far away, close to camera, or partly outside LiDAR range while background remains valid. | Inconclusive/insufficient on-person depth; no body result or invented geometry. |
| A01 | At a paused analysis point in Xcode, inspect native RGB dimensions, mask axes, inverse pose transform, depth/confidence dimensions, row strides, and camera calibration provenance in memory. Do not export/log the values. | The same-frame full-FOV mapping is demonstrably correct. Pose points on the subject map to the subject mask and corresponding depth, not background. Aspect equality alone is not sufficient evidence. If inspection is insufficient, add reviewed **temporary in-memory developer instrumentation** before approving this row. |
| A02 | With a steady visible subject, move limbs relative to background and briefly occlude one person region with a nearby object; restore it. | Mask/pose/depth remain associated with the current person and frame. Regionally missing/ambiguous depth rejects rather than passing on overall scene coverage. |
| A03 | Observe native-orientation segmentation with the upright portrait subject across supported camera resolutions. | Segmentation works with the explicit native `.up` mask contract. Unexpected rotated/cropped/square mask layout fails closed. Any transform change requires deterministic regression coverage before retrying this row. |
| A04 | Remove/degrade available person depth: low light, reflective/absorbing clothing, depth-obscuring condition, hands/feet in low-confidence areas. | Low/nonfinite/absent depth or confidence cannot count as valid coverage. Head/torso/leg regional failure prevents acceptance. Never infer missing body surface. |
| Q01 | Keep a correctly front-facing subject stationary with full framing and reliable on-person depth. | Front auto-capture only after stable duration/count and defensible face/bilateral-axis evidence; then sideways guidance. Record false rejections; do not call a skeleton a measured body. |
| Q02 | After front guidance changes, remain facing front; then present oblique and back-facing views. | No side candidate for repeated front, oblique/contradictory, back, or unknown orientation. A false acceptance blocks the gate. |
| Q03 | Turn sideways while keeping the same subject, camera, and framing; test turning left and right. Include expected shoulder/hip/ankle occlusion. | One-sided visibility can still satisfy framing. Side auto-capture requires an independently defensible bilateral depth cue. If occlusion prevents verification, remain inconclusive/retry; never treat the instruction to turn as evidence that turning happened. Record whether an ordinary side capture is feasible. |
| Q04 | Move the subject quickly, then slowly drift continuously. Move/rotate the phone quickly, then slowly drift it. Stabilize again. | Motion resets stability relative to the start of the stable window, not just the preceding frame. No accumulation of individually small movements into a false stable capture. Stable recovery works. |
| Q05 | After front capture, let the person leave; introduce a different person or materially change camera/framing/range. | Old front evidence is invalidated or remains unusable; no mixed-person/context pair. Context thresholds are not biometric identity proof. Undetected handoff is a blocking limitation for any claim of subject continuity. |
| L01 | Cancel while finding a person, during front analysis, immediately after front, during side analysis, and immediately as a candidate pair is produced. Reopen and retry each time. | Camera stops; temporary observations are discarded; no late result or reused front from the previous attempt. UI remains responsive. |
| L02 | Background/lock the phone during permission, active analysis, front-to-side turn, and review. Foreground/unlock. | Camera preview is covered in the OS app-switcher snapshot; camera stops and evidence is discarded. Explicit retry starts from front; no automatic resumption or stale completion. |
| L03 | Trigger an AR interruption (e.g. system camera contention), tracking failure, or session error where reproducible. | Session pauses and view becomes retryable. Interruption-end callbacks cannot silently restart it. Retry is a fresh attempt; record unavailable fault-injection cases as NOT RUN. |
| L04 | Rotate to landscape during capture and during the front/side transition; return to portrait and retry. | Attempt invalidates, clears observations, and asks for upright retry. No cross-orientation pair or misregistered point is accepted. Existing legacy landscape support is unaffected. |
| L05 | Hold an inconclusive scene until timeout; introduce inference delay under the debugger; then retry. | Timeout/retry instead of endless apparent progress. Results older than the freshness policy cannot capture a view. Old work may finish but cannot modify the next attempt. |
| R01 | Complete a candidate pair when evidence permits; choose Done, discard/retry, navigate back, and background from review. Cold-launch the app. | Review copy remains provisional, never avatar/fit success. No profile is generated or saved. Pair buffers release on each exit/discard; cold launch does not claim a saved scan. |
| R02 | Run repeated start/cancel/interruption/retry cycles under Instruments Allocations/Memory Graph; include a full candidate pair and denied/unsupported paths. | At most one analysis input plus accepted pair; no accumulating ARFrame/RGB/renderer or Vision-cache retention. Memory returns to a bounded baseline after work finishes; no retained controller/model cycle. Record actual memory observations. |
| R03 | Profile live capture, low light, and repeated retries using Time Profiler/Energy/thermal state. | UI/cancel remain responsive, no main-thread Vision/raster work, and no queued frame backlog. Record inference latency/freshness rejection behavior and thermal/battery observations. No unmeasured FPS or power claim. |
| R04 | Inspect the app sandbox and network activity before/after capture, cancel, background, timeout, review, and termination. Include existing saved avatar/legacy data. | No raw frame/depth/mask/recording files, sensitive logs, or scan uploads. Existing profile/default data unchanged. OS snapshot protection observed separately in L02. |
| U01 | Run with VoiceOver and large accessibility text. Exercise start, denial/settings, unsupported, retry, cancel, review, and navigation. | All actions have usable labels and alternatives; text scrolls without hiding recovery controls; no numerical body data, sensor diagnostics, scores, or measuring instructions appear. |
| U02 | Repeat key scenarios on the oldest supported iOS/device combination that supports the intended camera APIs. | Availability, permission, cancellation, alignment, and recovery behave consistently; unsupported combinations are rejected honestly. Missing hardware/version remains an explicit blocker for that coverage. |

## Evidence record template

```text
Commit / device / iOS build / Xcode SDK / configuration / date:
Case ID:
Expected state sequence:
Observed abstract state sequence:
Candidate emitted: none / front / side-pair-for-review
Result: PASS / FAIL / NOT RUN
Recovery observed:
Aggregate performance observation (if applicable):
Issue reference and required code/test change:
```

Do not attach body photos, screen recordings of people, raw depth/masks, calibration/landmark dumps, personal measurements, or identifying participant details.

## Stop and approval rules

- **Stop immediately** for a camera session after cancellation, stale work changing another attempt, wrong-person/incorrect-view acceptance, background-depth-only acceptance, raw-data persistence/upload, or a crash/resource growth. Preserve only nonsensitive reproduction steps and error categories.
- A front/side candidate is not a valid body model. If ordinary side-view orientation cannot be verified reliably, mark Segment 1B **NO-GO for reliable two-view capture** and document the unresolved failure. Do not add fallback measurements or approve arbitrary scene data to obtain a pass.
- Approval requires recorded device observations for permission/lifecycle, actual mask/pose/depth registration, wrong-view rejection, usable ordinary captures, recovery, privacy, memory, and accessibility. Thresholds must be justified or revised with evidence; synthetic tests alone cannot approve them.
- No numerical body accuracy target or avatar/garment-fit claim is part of this gate. Any later geometry work requires a separately reviewed task. Do not merge or proceed automatically.
