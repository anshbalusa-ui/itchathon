# On You — consumer scanning integration hardening

**Goal 1, 2026-11-22.** Focused lifecycle/state reliability, not another consolidation, scanner architecture or physical-accuracy claim. Product **On You**, native module/scheme **FitCheck**. Controlled preparation/start callbacks in tests are not camera evidence or successful personal scans.

## 1. Starting state and protection

Fetched all remotes before source edits. Latest main was `b3e0397eb6ac1ce8ab13b84e00a645e1a49a6e8c`. [PR #30](https://github.com/anshbalusa-ui/itchathon/pull/30) remained an open draft against main, head **`075db5abdaef95a0ae0fd9adee67c8bee16b1f7f`**, branch `integration/onyou-foundation-20261122`. PR #28 remained at `16dccd39162dfcb3519d3cfc8f7211446b6d5b24`; PR #29 at `45b5db23c53fc38198ee043d950881f40766f100`. No newer active scan branch or existing hardening branch was found at refresh.

Created **`feature/onyou-consumer-scan-hardening`** from the verified remote foundation in a separate `onyou-consumer-scan-hardening` worktree. The correct review base is the unmerged foundation branch, not old main. Snapshotted eleven pre-existing worktrees; unrelated fitted-shorts work had seven modified/untracked paths and is excluded. No reset, stash, force-push, direct main edits or merge/closure of existing PRs.

Read the existing consolidation, stationary refinement, platform architecture and execution roadmap before changes. Their historical receipts remain scoped to their original sources.

## 2. Already implemented — preserved

- Aashu's one stationary ARKit session, matched RGB/LiDAR, Vision person evidence, full-body calibration, camera-movement protection, turning-angle tracking, angular photo admission, front/side/back/other-side coverage and spatial guidance.
- PR #29's solo arming, five-second countdown, fresh-framing wait, local speech/VoiceOver/mute, excessive-turn guidance, direct missing-view arming and coherent native-pose/sample-ID filtering, as incorporated by PR #30.
- Native `PhotogrammetrySession`, exact photo/mask/depth archive input, output texture/bounds/scale/integrity checks, interactive review and explicit acceptance.
- Protected local storage, backup exclusion, transactionally replaced saved avatar, private failure messages and raw-work cleanup.
- PR #30's cached asynchronous legacy illustration, scene ownership and existing closet, automatic shirt scanning and illustrative garment/try-on integration. None is rebuilt or used as a synthetic successful personal scan.

## 3. Actual gaps and pre-change checklist

Classifications distinguish source support from physical proof. The checklist was recorded before production changes.

| Classification / exact gap | Existing behavior reused | Smallest change / affected files | Regression / expected improvement |
| --- | --- | --- | --- |
| **DEFECT:** `cameraReady` assigned its controller without applying `capturePaused`. A pause before readiness had no controller to affect. | Existing model pause Boolean and native `setPaused` | Project a pending pause to an accepted late controller; `BodyCaptureModel.swift` | Late controller remains paused until actual dismissal. Failing-before model regression confirms the missing projection |
| **DEFECT:** capture view only sent `.onChange` pause events. Initial inactive/prompt state and disappearance were not reported. | Existing `pauseCapture`, `scenePhase` and prompt calculation | Apply current state on appearance and pause on disappearance; `BodyScanCameraView.swift` | Real hosted view reports initial inactive and removal pause; failing-before assertions confirm both omissions |
| **DEFECT, source-supported:** pause callbacks lacked the capture-ID fence used by camera ready/update/finish/failure; an outgoing view could affect a newer attempt. | Existing generation UUID and flow's captured ID | Require matching ID in model setter and flow callback before model/voice-prompt mutation; model/flow files | Old pause cannot pause an active replacement or resume its current pause. Controlled regression covers the repaired boundary; no physical interleaving claimed |
| **MISSING COVERAGE:** actual countdown/native-start tasks were hard-wired to wall time, physical preparation and a final native controller. Existing status tests alone do not exercise ownership. | Real `BodyCaptureModel` and four native control methods | Constructor-only preparation/tick/uptime functions and `BodyCaptureControlling`; model/camera files | Actual coordinator can be deterministically driven without a global camera-success mode or bypassing production runtime calibration |
| **MISSING COVERAGE:** repeated recovery, stale recovery and processing failure/discard lacked coordinator-level assertions. | Existing archive retention, real coverage and missing-view handler, native cancellation and saved-avatar store | Generation-check the existing internally callable missing-view result boundary; actual-model tests | Retained IDs/direction/next ID survive repeated cycles; obsolete results are ignored; construction failure/retry/discard cannot save over the prior avatar |
| **MISSING COVERAGE, observed platform limit:** the first failure-path test reached the unsupported simulator's native constructor and crashed before lazy file reads could report an error. This was not a production-device failure. | Existing detached native construction and cancellation/unwind handler | One instance-only `makeSession` function returning the concrete Apple session, defaulting to the unchanged real constructor; model/tests | Controlled construction errors exercise real failure/retry, and delayed failure proves cleanup waits for unwind and cannot fail a new generation. Tests never fabricate sessions/poses/models |

**WORKING under source review, left untouched:** status freshness/arming policy; countdown cancellation and generation checks; duplicate-start suppression; reconciliation of in-flight native results; native serial sampler/calibration gates; turn/coverage/retained archive; native pose consistency; prepared-scene cancellation and store transaction. New tests exercise their coordinator connections rather than duplicate implementations.

**UNVERIFIED PHYSICALLY:** native camera/AR interruption behavior, current-frame admission during real pause/resume, native sample interpretation, human reconstruction, completeness, metric scale and likeness. **OUT OF SCOPE:** largest-text Body layout, studio, statistical completion, grading, physics and publishing.

## 4. Changes implemented

### Existing model, not a replacement coordinator

`BodyCaptureModel.init(prepareCapture:countdownTick:uptime:makeSession:)` supplies instance-only boundaries. Defaults retain actual capability checks, camera authorization, two-gigabyte guard, protected fresh work directory, the real Apple native-session constructor and existing cleanup. No launch argument or global flag enables successful camera capture. A preparation result belongs only to that attempt; late/canceled preparation removes its newly owned directory, and a late error cannot fail the replacement generation.

`beginCountdown` still displays five seconds and waits for five ticks. It does not admit samples. Waiting remains event-driven; `beginCaptureIfReady` still requires a live controller, unpaused matching phase, no current start task and the unchanged fresh-calibration policy. Native `BodyCaptureController.startScanning` still performs the original real calibration, portrait, tracking and camera-reference checks.

`cameraReady` applies an already-pending pause before considering start. `setCapturePromptVisible(_:captureID:)` rejects obsolete view events. Native start completion still reconciles its real Boolean result even when a prompt paused the runtime; generation/phase checks prevent old results clearing a replacement task.

`missingViews(_:in:keeping:captureID:)` is the existing retention operation with an explicit phase/generation boundary. The real native caller passes its existing token only after the unchanged native-pose consistency check. No native poses, IDs or successful models are invented by production code.

### Surface lifecycle

`BodyScanCameraView` sends current combined prompt/inactive pause on appearance and pauses on disappearance. Its existing Help/scene observers remain. `BodyScanFlowView` rejects an outgoing capture-ID callback before updating either prompt/speech state or the model. No layout redesign, new tap, countdown repetition or voice engine is introduced.

## 5. Meaningful regression coverage

New `Tests/BodyCaptureModelTests.swift` drives the actual model with explicitly controlled preparation/start and a logical countdown clock. It covers:

- Arming before framing, exactly five ticks, long waiting, stale/future evidence rejection, one native start despite repeated updates.
- Cancel/rearm with the old noncooperative sleep finishing late; cancel during framing wait; prompt/inactive pause in either pending state.
- Late controller pause inheritance; native start success/refusal while paused; active native refusal waiting for fresh evidence without another countdown.
- Old native start unable to clear a replacement countdown; old ready/update/finish/failure/pause callbacks unable to alter the new generation; background during start.
- Duplicate completion finalizing once and cancel-before-processing-publication cleanup.
- Two scripted missing-view result cycles retaining actual archive ID sets, negative turning direction and monotonic next-ID metadata; stale recovery cannot replace the newer request.
- Controlled native-construction failure/retry, rejected save/discard and unchanged previously saved authored avatar/hash/reopen; late preparation success/error ownership.
- Noncooperative native construction delayed until after cancellation/new scan: work remains until unwind, then is removed without publishing a stale model or failing the replacement generation.
- Real hosted production capture view applying initial inactive and disappearance pause, with camera-free rendered attachment.

Metadata-only archives deliberately have no photos, native poses or successful model; they exercise event/retention/error boundaries, not reconstruction. Next-ID assertions establish archive retention, not the private AR runtime's actual resumed-directory allocation. Existing turn/alignment/store regressions are reused for their separate contracts.

`UITests/ScanCameraUITests.swift` adds one Debug simulator smoke: open/close/reopen the real consumer scan flow and return to the existing explicitly synthetic avatar. Unsupported hardware remains unsupported; the test does not start a fake scan, request personal data or assert incidental wording. Existing physical tests remain intact and are not selected.

## 6. Existing behavior and safety preserved

| Contract | Preserved |
| --- | --- |
| Coverage | 60 distinct photos, three front-region full-body samples, 32/36 bins, max 20-degree gap, existing angular separation and all native-pose coherence thresholds |
| Capture | Same ARKit session/format, paired RGB/depth/mask orientation, person/pose/arm/depth/framing checks, locked camera reference and original photo limit |
| Recovery | Same admitted-ID retention, excluded/rejected pose handling, direction and target logic; no required second full turn or resetting valid photos |
| Reconstruction/review | Same native engine/poses, texture/bounds/scale checks, detached scene preparation, explicit acceptance and no template fallback |
| Saved data | Same protected/backup-excluded stores, hashes and atomic active record; last saved asset changes only through validated explicit save |
| Privacy/lifecycle | Same permission, private errors, raw-photo cleanup and native-work-unwind cleanup; DiskSpace E174.1 unchanged and not duplicated |
| Other systems | Legacy measurements/storage, reference mesh, garment capture/closet/try-on and data formats untouched; no account, network service or evidence retention for training |

## 7. Verification status

New failing-before evidence: unsigned Debug, iPhone 17 simulator/iOS 26.5/x86_64, source fingerprint **`fa416eac3b49e597cab65784df1afaec838b514a2da836755d9b3bf338c03ebf`**. `PauseBeforeRepair.xcresult` executed **two tests, both failed** (three pause assertions): late-controller pause inheritance and initial/disappearing capture-surface pause. Production testability boundaries were present; pause repairs were not. Source fingerprint remained unchanged during that run. This was actual controlled reproduction, not a physical scan.

### New bounded results

Final unsigned Debug environment: iPhone 17 / iOS 26.5 / x86_64 simulator. The final fingerprint in the receipt table was identical before/after execution. Selection: 16 new actual-coordinator cases, two existing status cases, three existing turn/native-alignment cases, one existing store-integrity case and one consumer app smoke.

| Receipt | Exact source fingerprint | Actual result |
| --- | --- | --- |
| `PauseBeforeRepair.xcresult` | `fa416eac3b49e597cab65784df1afaec838b514a2da836755d9b3bf338c03ebf` | Two executed, both failed; three pause assertions reproduced the pre-repair omissions |
| `Goal1Affected.xcresult` | `c0d1f26047fdeb756634ce76b8fd8960b6a14444b826272e5b8b87eefa6e85cd` | 21 passed, one crashed in unsupported `PhotogrammetrySession` construction; not green |
| `Goal1Final.xcresult` | `13e16477fda0a956ae5a4c1434190100681541ada01646330eb5fbd799eb3878` | 23 passed; the native-construction boundary is controlled, never a fabricated success |

The earlier assumption that absent files would fail before native construction was incorrect: `AvatarScanInput.validate` checks counts/associations, and archive reads are lazy. Exported SIGILL diagnostics identify `PhotogrammetrySession.__allocating_init(input:configuration:)` inside the detached setup. Production default preparation already rejects unsupported hardware. The repair is a focused verification boundary, not a new fallback or a claim that native reconstruction ran in Simulator.

Local evidence is outside Git at `/Users/anshbalusa/onyou-consumer-scan-hardening-evidence-20261122`: all three result bundles, source/input/summary/tests JSON, crash diagnostics and final exported attachments. Inspected actual final production chrome with disabled Start under initial inactive state, actual app's unsupported scan screen on re-entry, and preserved explicitly synthetic avatar after close. These establish software state/UI behavior, not a personal scan.

Exact final command, from the hardening worktree:

```sh
xcodebuild -project 'On You.xcodeproj' -scheme FitCheck -configuration Debug \
  -destination 'platform=iOS Simulator,id=D5BE86CA-76FC-4C6A-BD88-5D29FFF910F5' \
  -derivedDataPath /Users/anshbalusa/onyou-consumer-scan-hardening-evidence-20261122/Derived \
  -resultBundlePath /Users/anshbalusa/onyou-consumer-scan-hardening-evidence-20261122/Goal1Final.xcresult \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO \
  -only-testing:FitCheckTests/BodyCaptureModelTests \
  -only-testing:FitCheckTests/BodyScanUXTests/testStartCanBeArmedBeforeFramingButCaptureRequiresCountdownAndFreshCalibration \
  -only-testing:FitCheckTests/BodyScanUXTests/testFinishingDoesNotEnableStartAndKeepsCompletedViews \
  -only-testing:FitCheckTests/BodyCaptureTurnTests/testMissingBackSectorKeepsAcceptedViews \
  -only-testing:FitCheckTests/BodyCaptureTurnTests/testAlignedPosesMustSurroundSubject \
  -only-testing:FitCheckTests/BodyCaptureTurnTests/testYawInconsistentNativePosesCannotSupplyThePhotoFloorAndRemainRecoverable \
  -only-testing:FitCheckTests/AvatarScanTests/testTexturedGeometryPersistsAndCorruptionFailsClosed \
  -only-testing:FitCheckUITests/ScanCameraUITests/testConsumerScanEntryCanCloseAndReopenWithoutSaving \
  test -quiet
```

No full Debug/Release, distribution, benchmark, personal body scan or physical garment campaign was run. PR #29's 80 passes/two native skips and PR #30's five-case consolidation smoke remain historical results for their own sources, not this branch. Native-session construction/output, real in-flight AR image admission and cancellation during actual model preparation remain separate native/device validation gates.

The final scoped diff retains all existing meaningful tests and touches only four scanner/controller/view files, new model tests, one focused UI smoke and this handoff/roadmap. Whitespace validation passed. All eleven pre-existing worktrees retain their original tracked/untracked path statuses, including the seven unrelated fitted-shorts work paths. No source or privacy manifest change was made outside this scope.

## 8. Future hardware and native requirements

Authorize compatible-device checks later: initial camera permission and denial, lock/inactive/background/foreground, Help/discard during countdown/start/capture, native AR interruption/recovery, actual sample admission and camera drift, fresh framing under constrained space/light/occlusion, raw work cleanup while native work unwinds, retry/missing-view recovery, native USDZ preparation/cancellation and explicit save with an existing avatar.

Still establish RGB/mask/depth/intrinsics interpretation, native reconstructed viewpoints for a stationary camera/turning articulated human, complete visible body, front orientation, repeatability, real metric error/likeness and independent reference uncertainty. Controlled tests and Apple's rigid-object/turntable support do not prove those properties. Garment visualization remains illustrative, not validated fabric/drape/pressure/sizing/fit.

No iPhone, LiDAR device, person scan or new body data is required from the user to complete this source-hardening assignment.

## 9. Next milestone

After the focused passing run, no further demonstrated code-level blocker remains in the reviewed coordinator paths. This is not production-readiness or physical scan proof. Native human reconstruction remains a separate validation gate. **Goal 2 — On You Studio Foundation** can proceed independently with labelled, licensed standardized nonpersonal models, without waiting for statistical personal completion or claiming validated fit. Use the existing execution roadmap's Goal 2 scope; do not re-run consolidation or rebuild Goal 1 features.

### GitHub review delivery

- Branch: `feature/onyou-consumer-scan-hardening`.
- [Draft PR #31](https://github.com/anshbalusa-ui/itchathon/pull/31) targets `integration/onyou-foundation-20261122` at `075db5abdaef95a0ae0fd9adee67c8bee16b1f7f`, because PR #30 remains unmerged.
- Code/handoff integration commit: [`7ff722599ef03fedc61168de644d06fe8c4f3deb`](https://github.com/anshbalusa-ui/itchathon/commit/7ff722599ef03fedc61168de644d06fe8c4f3deb). The PR contains eight scoped files relative to its foundation base, not the foundation's changes again.
- This delivery receipt is a documentation-only commit after the real PR URL existed. [PR commits/current head](https://github.com/anshbalusa-ui/itchathon/pull/31/commits) identifies the final publication revision; the verified compiled source fingerprint remains unchanged.
- Main and existing PRs #28/#29/#30 were not modified, merged or closed. No automatic merge is authorized or performed.
