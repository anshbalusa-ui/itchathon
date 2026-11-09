# On You — try-on, draping, capture performance and UX

## Review status

**Complete for an illustrative collaborator demo.** The final frozen-source Debug/Release/device-SDK/privacy matrix passed, all original current-main unit identities are preserved, and final compact OS-dark/largest-text journeys passed without weakening assertions. Actual unedited screenshots and an inspected 53-second simulator recording are available. Draft PR #26 is published; the verified Debug app is open in Simulator. Physical capture, likeness and garment-fit validation remain unclaimed.

## Source of truth and branch audit

- Repository: `anshbalusa-ui/itchathon`.
- Starting verified `main`: `9b97ab387649a5da26ab01285c7957ae454b19c5` — **Wire try-on preview into closet and scene**.
- Dedicated implementation branch: `fix/tryon-draping-scan-performance-20261107`.
- Published implementation commit: `aefcb9fc09e8a5874015085a886fe1ca4b50bb84`.
- New draft PR: [#26 — Repair native avatar try-on, illustrative draping and capture UX](https://github.com/anshbalusa-ui/itchathon/pull/26), targeting `main`. Published for teammate access before the recovered repeat finished; the final complete receipt below now passes. No merge was performed. Subsequent handoff-only receipts remain on this same repair branch.
- Actual application: **On You**, module/target/scheme `FitCheck`, generated project `On You.xcodeproj`, specification `Project.json`.
- Bundle identifier: `app.bitrig.new.0bab6520-e754-44f9-acd8-d1ecceeda6e3`; product/executable `On You.app` / `On You`.
- PR #24 was already merged. PR #25 remains the separate open draft **M1: Smooth measurement-driven human avatar demo**, branch `feature/measurement-avatar-demo-m1`, observed head `21e5728afbd0d2c1cfe367437ab796905537ddcb`. Direct authenticated GitHub API refresh confirmed its head, base, draft/open state and unchanged update timestamp.
- M1 and current main diverged after `40feaf4931614637c3e1dc05407af2660eb56f19`. No M1 merge/rebase, PR #25 modification, or change to `main` is part of this repair. The CC0 human resource was already present on current main; the repair does not import M1's measurement-avatar implementation.

The live PR #25 changed-file audit overlaps this repair only in `README.md` and `Scripts/verify_development.py`. Those documents/build instructions need intent-aware reconciliation if M1 is reviewed later: M1 still describes the older project structure. This repair does not modify its measurement-avatar files, internal development views, Metal scene session or historical Friday handoff. No conflict-free merge of the divergent draft is claimed.

## Original reproduced failure

Untouched main passed **362/362 Debug unit tests**, with no skips. This is the actual On You baseline, not M1's separate historical 381/18 result.

A wholly authored textured USDZ was admitted through `ScannedAvatarGeometry` and `AvatarScanStore`, and a shirt was persisted through `ClosetStore`. The original builder then failed its rendered-body Vision request with **Vision Code 9: Unable to setup VNDetectHumanBodyPoseRequest**. Simulator diagnostics identified unavailable `cnn_human_pose.espresso.weights`. Shirt construction, attachment and a first visible garment frame were not reached. Those stages are not reported as successful zero-duration work.

The original algorithm additionally required face observations while selecting a body pose, rendered up to eight avatar views, and repeatedly traversed/sampled the surface. `BodySceneView` could silently omit the garment when its optional geometry factory failed. These are separate architecture/product risks from the observed simulator Vision failure.

The cartoon shirt fixture is **not** recognized successfully by the native garment model. Its authored ground-truth observations are explicit synthetic inputs, validated against its actual alpha contour and bound to its exact image hash. Legacy shirts without retained observations still undergo genuine native inference; unrecognized images fail rather than receiving replacement clothing. The existing licensed `GarmentIQ-Shirt.jpg` remains the real model-inference regression/benchmark input.

### Concrete repair findings

- A canonical-yaw owner now wraps, rather than overwrites, the saved model's normalization hierarchy. Garment and rendered body share the resulting metric frame.
- Independent flat-panel warping produced visible shoulder/sleeve spikes and holes. The continuous shared-vertex shell replaced that implementation; the broken mapper and optional mesh-to-node success path were removed.
- On body B with the Tide shirt, a **connected but concave crotch section** collapsed a radial row from a full lower-body envelope to a tiny central pocket. Interpolated clothing then crossed the observed surface and correctly failed the 65 mm pushout bound. Lower clothing now spans connected concavities as well as separate leg loops. The body is not filled or modified, and the rejection bound is unchanged. An intermediate Mac-native smoke produced 31,065 vertices, 60,080 triangles and zero degenerate faces; subsequent iOS fixture runs also rendered that combination successfully.
- Pixel inspection found the Detail stage displaying **Pass 1 / Body circle** after one completed circle. `currentPass` counted a paused completion instead of the next active pass. The corrected transition keeps a paused first circle at 1 and an active detail circle at 2. A failing-before/passing-after Mac-native smoke exercises the actual shipping status implementation; the iOS transition assertions passed without changing capture admission.
- Two new geometry tests initially had SDK-fixture defects, not product transform/index failures. `SCNBox` exposed a parametric unit-cube vertex source rather than its requested baked dimensions; the transform test now supplies explicit saved-mesh-style indexed vertices and keeps all analytic bounds assertions. Exact antiparallel `SCNNode.look(at:)` left the stress test's rear camera facing away; explicit orthogonal poses keep the rendered-pixel assertion intact. An 80,802-vertex Mac-native diagnostic rendered 13,294 front and 33,840 rear cloth pixels with genuine four-byte indices; the separate iOS UInt32 front/rear regression passed.
- Later multi-fixture visual inspection exposed a horizontal shelf on the longer Coral shirt. Raw torso contours abruptly switched to convex clothing at the hip marker. A constant observed concave prism reproduced a **62.4 mm garment jump across unchanged body sections**. Clothing now uses the same convex envelope above and below that boundary; the original upper-body observed-ray admission runs before convexification, so missing scan coverage cannot be hidden by a hull. The exact shipping Swift smoke now reports **0 mm jump**, while observed body depth stays 40 mm on both sides. A permanent analytic regression preserves this invariant. The in-progress full matrix was deliberately stopped for this substantive visual repair, not reported as passed.
- SwiftUI's `ContentUnavailableView` exposed the visible failure buttons without their requested test accessibility identities. Recovery now uses explicit scrollable native controls; success still requires a prepared garment, never an unadorned avatar.


## Actual app journey

**Body → saved textured avatar → Closet → shirt → Try on → rotate/front/back/reset → hide/show → close → reopen.**

This is the main On You SceneKit path, not the older internal Metal showcase. A ready result owns both validated avatar and garment scene templates. Visibility changes hide the existing garment node; they do not reload USDZ or reconstruct clothing. Each presentation receives its own scene nodes, camera and coordinator. Dismantling disconnects the view's scene, point of view and delegate and detaches owned nodes.

Garment details put the try-on/retake actions ahead of comparisons. Photo-only garments do not acquire metric scale. Missing avatar and missing photo states offer scan/retake recovery instead of a successful bare-avatar preview. Error recovery uses accessible, scrollable native controls. Closing, rapid re-entry and backgrounding invalidate old work; `TryOnModel` cancels its owned task as well as guarding result publication by generation.

## Coordinate and observation contract

- Native USDZ loads use meters and Y-up and retain the existing calibration admission.
- Normalized ground is Y = 0. The canonical front is +Z.
- The person's left is +X; photograph-left is −X.
- Triangle extraction includes geometry on the supplied root and all descendants, complete transform ancestry, supported float layouts and UInt8/UInt16/UInt32 indices. Malformed offsets/strides/indices and nonfinite coordinates reject.
- Canonical yaw is applied to an owner **outside** the normalized saved root, so normalization translation is not accidentally composed after canonical rotation. Clothing is already generated in that canonical coordinate system.
- Horizontal PCA establishes the candidate frame; observed foot-versus-ankle geometry establishes front. Supported standing surfaces must provide observable separated arms, shoulders, neck and lower-body sections. These are geometric feature references, **not validated anatomical joints or body measurements**. Missing observations cause actionable failure, not fabricated anatomy or a generic-body substitute.

## Garment shell

`TryOnGarmentShell.swift` constructs a continuous outer surface from the actual saved body's horizontal intersections and observed arm sections. Shirt width, length, sleeve span, image contour and admitted observations affect the generated geometry.

- Torso envelopes use 64 observed radial samples, bounded illustrative clearance and interpolation between sections.
- Below the lower-body reference, a garment envelope may bridge the air between observed legs. This models cloth spanning space; it does not add hidden body geometry.
- Observed arm envelopes join the torso through a bounded smooth union.
- A bounded marching-tetrahedra lattice creates shared shoulder/torso/sleeve vertices rather than independently warped flat panels. Neck, cuffs and hem are intentional openings.
- The front neckline is derived from observed image alpha, not unadmitted low-confidence model point 0. The shallower plain rear is explicitly inferred because no rear garment photograph was captured.
- Unsupported UV locations are projected onto actual opaque source-image pixels, preventing the non-convex flat sleeve mask from punching accidental alpha holes into a sewn junction. No replacement photograph or commercial texture is generated.
- Degenerate faces and unused vertices are removed; finite positions/UVs, valid indices and normals are required before a ready scene is published. SceneKit uses UInt32 elements rather than silently omitting meshes beyond 65,535 vertices.
- The 12 mm illustration lattice, bounded offsets and smoothing are **not accuracy claims**. No fabric dynamics, tension, pressure, size recommendation or physical-fit validation is implemented.

Surface work is indexed by 3 mm height rows and 4 mm X-query bins. Index entry budgets are bounded; a depth-index optimization never changes the underlying exact segment intersection calculation. Cancellation is checked during substantial geometry loops.

## Loading, inference and ownership changes

- One serialized `GarmentLandmarkService` lazily loads the existing native model. Heatmaps are decoded through their actual typed memory strides instead of repeated boxed-number subscripts. Existing confidence and quarter-pixel decoding rules remain.
- New captures retain garment-only observations bound to the exact uncropped foreground PNG SHA-256. Retaking replaces image identity and evidence together. A substituted image cannot reuse old observations.
- Try-on caches are presentation-owned and bounded to one avatar, one image/pattern and one ready scene. Keys include scan identity, immutable artifact hash, height calibration, URL, garment/image identity, dimensions and evidence. Cache reuse still checks the saved file and exact image binding. Clearing the presentation releases the caches; no global personal-scene cache is introduced.
- `PreparedAvatarScene` performs bounded file admission, USDZ parsing and texture inspection off the UI actor. The reconstruction review reuses its already validated prototype rather than parsing the finished file again in a view update. Render owners receive clones of an immutable unattached prototype.
- Body and try-on previews pause when inactive. The shared Core Image context does not cache intermediate photographs.

## Capture and scan UX

The existing **Frame → Body → Detail → Build** structure remains. Body guidance now distinguishes actual SDK lighting, movement, too-close/too-far, selection and tracking feedback. Out-of-view feedback is neutral framing guidance; it does not invent a direction or target distance. The person stays still with arms slightly away; the helper moves around them while keeping head and feet visible.

Pass checkpoints, capacity recovery, next-pass actions and interruption recovery remain tied to native capture state. The two-pass, at-least-60-image, positive finite depth and accepted reconstruction mapping requirements are unchanged. Native model output must match the requested destination and accepted aligned sample URLs; invalid/skipped images do not become admitted evidence.

Privacy-safe stage diagnostics cover framing, selection, body/detail passes, checkpoint waiting, capture finalization, photo preflight, reconstruction, artifact/texture admission and finished-avatar loading. Native reconstruction and texture generation remain Apple's work; no simulator result is presented as a physical capture or reconstruction-speed measurement. The native photograph initializer was already asynchronous on main; the repair moves app-controlled preflight normalization/depth inspection into a cancellable worker rather than claiming to have made Apple's loader synchronous-to-asynchronous.

Shirt capture distinguishes search, recognition, landmarks, metric depth, projection, stabilization and review. It retains one in-flight analysis and generation-based stale-result rejection. The existing strict **greater-than-0.7-second** frame separation and **three agreeing distinct captures** are preserved. Portrait image coordinates are explicitly mapped back to native camera/depth UVs before projection. Foreground cropping no longer changes the image coordinate canvas. Retake, tracking changes and foreground recovery reset consensus; imported photos never acquire invented metric depth.

## Synthetic fixture boundaries and reproduction

`DevelopmentAssets/OnYouTryOnFixtures/PROVENANCE.json` records source, SHA-256 values, license, authoring and admission boundaries. Both bodies derive from the already pinned CC0 MakeHuman resource; B changes real XYZ vertex positions. The two shirt images, colors and dimension sets are authored fictional data. The unsupported-pose artifact is a textured box, not a simulated person.

The Debug fixture entry seeds **unique protected temporary stores** and a separate defaults suite, then opens the normal app. It does not read or replace personal stores, fake native camera completion, or promote a fixture into a personal avatar. The visible synthetic disclosure accompanies this route. Authored 72-image/two-pass record metadata is a fixture contract input, not proof that photographs were captured.

```sh
Scripts/launch_onyou.sh --fixtures
Scripts/launch_onyou.sh --fixtures --body b
```

The helper reads actual `Project.json` product metadata, builds unsigned Debug, boots an available iPhone simulator without erasing it, installs and launches the real app. `--app` accepts a prebuilt matching Debug simulator app and rejects stale/Release products. Additional fixture scenarios are `missing-avatar`, `photo-only`, `missing-photo` and `unusable-pose`.

The build/install/launch branch was exercised successfully on the fresh owned iPhone 17 `354553A7-2CE9-4FF6-B196-D9CC74C10712`:

```sh
Scripts/launch_onyou.sh --simulator 354553A7-2CE9-4FF6-B196-D9CC74C10712 \
  --derived-data /Users/anshbalusa/onyou-tryon-artifacts-20261107/LaunchHelperDerived --fixtures
```

This host used XcodeGen 2.46 from the complete local `Toolchain/bin` copy under the evidence root; no global security setting or developer credential was changed. A brand-new simulator finished migration but its first install acknowledgement exceeded the original 120 s bound; `get_app_container` proved installation had completed. The helper now allows a bounded 300 s installation and the actual build/install/launch command succeeded with a live app PID and inspected Body pixels. Existing data is never erased and failed commands remain errors.

Recreate authored assets without downloads or camera access:

```sh
xcrun swift Scripts/generate_onyou_fixtures.swift /tmp/OnYouAuthoredFixtures
```

The output directory must be new/empty. Native USDZ packaging can change metadata bytes; the pinned source geometry, declared scale and authored images are reproducible. SceneKit exporter warnings are not substituted for actual admission checks.

The opt-in benchmark command temporarily installs its own probe in a dedicated worktree and removes it on exit. It is not part of the normal regression suite:

```sh
Scripts/benchmark_onyou.sh --simulator UDID --output NEW_EVIDENCE_DIRECTORY
```

`--repo BASELINE_WORKTREE --mode baseline` measures the same native recognition/ring workloads on original main. Its RGB-only HEIC preflight workload must reject absent depth; it is not a reconstruction success fixture. Measurements are simulator/process observations, not phone timings.

## Privacy, Release and hardware limits

No uploads, external analytics, face-photo intake, biometric matching, face stitching, payments or retailer integrations are added. Scan/closet protection and backup exclusion remain. Synthetic fixture code, flags and artifacts are Debug-only; normal Debug/Release still open the existing On You app. The reviewed production human resource remains available for main's pre-existing manual/example body; it is not incorrectly classified as a newly leaked Debug asset.

Real-device body capture, reconstruction duration, likeness, pose coverage and garment depth repeatability remain unvalidated here. A clothed textured scan does not expose hidden anatomy. Physical garment-fit research still requires validated body/garment measurements, fabric properties, controlled comparisons and real hardware evidence. No face collection is justified by this repair.

## Verification provenance and native platform limits

Evidence root: `/Users/anshbalusa/onyou-tryon-artifacts-20261107`. The recovered focused run is `RecoveredTryOn.xcresult`; `recovered-summary.json` records the actual 27/27 result. Its exported `RecoveredEvidence` contains real iOS SceneKit frames, app journey screenshots and shipping camera-chrome component captures. The component captures use an authored camera-free backdrop and are **not physical camera footage or completed scans**.

The earlier `FullVerification/verification-bmqcw0ol` attempt was interrupted during native simulator execution and has no finalized aggregate test result. During that incident, some host tools and simulator processes stopped before `main`; signing, debugger-free test action and safe owned-simulator restart attempts did not establish a causal diagnosis. Later the native launch helper returned a live PID, the actual Body surface was inspected, and all 27 focused cases passed. The incident is retained as historical environmental evidence, not reported as a current product failure or a successful full-suite run.

The original paired profiling attempt `BaselinePerformance2/Performance.xcresult` completed **3 profiling cases / 1 failed profiling case / 0 skips**: Apple's native `PhotogrammetrySample` initializer threw `unsupported` on this simulator. No photo preflight or reconstruction success occurred. The corrected opt-in report explicitly records native sample initialization failure, its actual elapsed time, and **depth admission not reached**; it does not synthesize native samples or turn that time into a reconstruction-speed claim. Production regression cases and depth validation remain intact.

## Paired simulator performance report

Raw receipts: `BaselinePerformance4/Performance.xcresult`, final-contour `FinalPerformance2/Performance.xcresult`, each directory's `summary.json` and `attachments/`, and `performance-comparison.json` under the evidence root. Both opt-in profiling harnesses completed **4 passed / 0 failed / 0 skipped / 0 expected failures**. This means the measurements were collected correctly; it **does not mean original main produced a garment**. Earlier contour measurements remain in `FinalPerformance` and `performance-comparison-pre-contour.json`, not substituted for final results.

Environment: the same owned iPhone 17 / iOS Simulator 26.5 (23F77), x86_64, unsigned Debug, sequential baseline then repair. “Cold” is a fresh builder or first model load in that process, not an erased simulator or flushed OS cache. Warm fixture runs reuse the same bounded builder and exact saved inputs.

### Feature result and stage reachability

All four baseline pairs, cold and warm, failed `VNDetectHumanBodyPoseRequest` setup. The opening-stage progress boundary was observed, but photo processing, surface extraction, garment generation, preparation and a successful first garment frame were **not reached**. The 118–291 ms cold failure durations are not successful preview latencies and must not be compared as an end-to-end speedup.

| Operation | Original main | Repair | Interpretation |
| --- | --- | --- | --- |
| Saved avatar opening | Cold opening-stage span 34.8–46.3 ms; no isolated artifact timer | Actual asset stage 29.6–40.8 ms | Both open the real saved artifact; timing scopes differ |
| Body feature determination | Vision setup fails; no completed pose | Observed geometry references 734.0–857.5 ms | New functioning path, not a completed-pose speed ratio |
| Shirt photo, pattern and surface work | Not reached | Per-fixture stages below | Exact retained observations validated, not fabricated native recognition |
| Garment generation / preparation | Not reached | Actual mesh and native scene below | No unrelated mannequin or canned garment fallback |
| First garment pixels | None | Cold offscreen 7.44–9.00 s; same-builder warm 27.8–70.0 ms | Genuine SceneKit frames, checked against garment-hidden pixels |
| Rotation frame | No garment to rotate | Warm non-front offscreen snapshots 8.4–23.1 ms | Native 480×720 snapshots, not a guaranteed interactive FPS |
| Native reconstruction preflight | Native initializer unsupported | Native initializer unsupported | Depth admission and reconstruction not reached; no speed claim |

### Each supported synthetic pair

Milliseconds, cold builder unless stated. `Photo / pattern` separates exact PNG opening/binding from authored contour/observation validation. Captured-observation fixtures do not run the native landmark model; a zero prediction field means **intentionally not invoked**, not instantaneous model inference.

| Body / shirt | Avatar | Pose | Surface | Photo / pattern | Mesh | Scene | First offscreen pixels | Warm builder / first pixels |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| A / Coral | 40.8 | 771.1 | 56.2 | 2.0 / 176.7 | 6976.4 | 339.0 | 8449.1 | 12.2 / 70.0 |
| A / Tide | 34.1 | 734.0 | 52.9 | 2.1 / 204.6 | 6023.9 | 323.7 | 7442.6 | 12.3 / 44.5 |
| B / Coral | 31.0 | 857.5 | 65.4 | 1.9 / 225.0 | 7435.9 | 313.4 | 9002.6 | 6.7 / 27.8 |
| B / Tide | 29.6 | 776.6 | 52.0 | 3.0 / 244.3 | 6300.4 | 252.1 | 7726.9 | 11.5 / 42.8 |

Each pair produced real front, back, left, right and three-quarter garment frames. The exported 20 cold-frame PNGs are in `FinalPerformance2/attachments`; warm runs also exercise actual rendering and garment-hidden comparison.

The final `FinalVerification4` app UI run observed first shirt pixels at a **19.77 s upper bound** and dismissal/reopening at **18.84 s**, including XCTest interaction, polling and screenshot overhead (`FinalPassingUIEvidence/58018399-3CA2-4A21-85E3-F19C0A8A920A.txt` and `C571B1E9-449B-42A5-B5F7-A117447B7C2B.txt`). These UI observations are separate from offscreen timing and show host/run variance, not phone latency. Dismissal clears the presentation-owned cache, so the 6.7–12.3 ms same-builder result is **not** promised for a closed/reopened screen. Initial mesh generation remains the dominant Debug cost.

### Identical workloads and resource observations

| Workload | Baseline | Repair | Result |
| --- | ---: | ---: | --- |
| 101 identical 64-ray section constructions, cold | 943.4 ms | 469.2 ms | Same finite/clearance invariants |
| Same construction, mean of two warm runs | 921.1 ms | 426.4 ms | Observed **53.7%** reduction for this exact workload |
| Licensed native garment model, first load | 7331.8 ms | 6255.0 ms | Process/model cold, OS cache not controlled |
| Licensed photograph, first detection | 6331.6 ms | 4590.5 ms | Genuine existing model, not authored fixture observations |
| Same photograph, two warm detections | 6506.9–11702.6 ms | 4381.0–4469.1 ms | Observed improvement with substantial baseline variance |
| Foreground image processing, two warm runs | 353.7–515.7 ms | 268.0–276.8 ms | Shared context, no coordinate-changing crop |
| Recognition workload process CPU, user + system | 99.85 s | 80.23 s | Cumulative CPU across three runs, not wall time |
| Process peak RSS after recognition | 530.5 MB | 530.6 MB | High-water mark; effectively similar, not proven allocation savings |

Final native recognition still spends 4.21–4.40 s in model prediction and 150–159 ms in typed decoding on this Intel simulator. The entire detection difference cannot be attributed to Swift decoding alone. These are small paired samples, not phone benchmarks or statistical performance guarantees.

The process had already loaded the model before saved-fixture runs, so its unchanged RSS high-water mark cannot establish mesh-only or live GPU memory usage. Temporary/GPU allocations were not independently traced. Ownership/cancellation and detached-node regressions provide the separate lifecycle evidence.

The native HEIC probe records `RealityFoundation.PhotogrammetrySample.InternalError.unsupported`, `native_capture_supported: false`, and `admission: not_reached` for both versions. No real scan, Apple reconstruction, texture-generation throughput or full native preflight duration is claimed. The application-controlled changes are cancellable off-UI preflight, eliminated redundant finished-avatar parsing, bounded inference scheduling, reusable model/image work and indexed surface construction; physical capture/reconstruction timing remains hardware work.

## Known limits and remaining validation

- This is a static illustrative shell, not cloth physics. The 12 mm lattice, inferred plain rear and single front photograph cannot establish fabric stretch, folds, pressure, tightness, hidden anatomy or a recommended size.
- Supported standing geometry must expose sufficient neck, shoulders, separated arms, feet and torso evidence. Unsupported or ambiguous surfaces fail with recovery; there is no generic-body success fallback.
- Authored garment observations are fixture ground truth, not native recognition results. The separate licensed photograph exercises the actual model. Real clothing/background/depth variability still requires controlled device evaluation.
- First uncached Debug construction is substantial. Same-builder reuse is fast, but dismissal intentionally clears the private presentation cache. Neither offscreen frame time nor XCTest screenshot timing is a phone latency guarantee.
- The simulator cannot validate Object Capture framing/depth, two real capture passes, native photogrammetry preflight, reconstruction throughput, texture fidelity, likeness or depth-backed garment repeatability. Shipping guidance components and deterministic admission/cancellation boundaries are tested independently.
- Real-world fit research still needs consented, calibrated ground truth; repeated measurements across poses and clothing; garment construction and fabric properties; and comparison against physical fitting. No face-photo intake, face matching, personal-scan claim or accuracy claim is added.

## Complete verification receipt

Final receipt: `FinalVerification4/verification-f6w46tyn/verification.json`, `mode: fresh-local-builds-and-tests`, frozen source SHA-256 `f068488ed13d24e875a60e58557593a8a409cb984aa17577da30a5c5a264e1ea`. This run includes the final compact button padding and bounded bidirectional XCTest scroll driver. The earlier complete `FinalVerification2` receipt is retained as historical evidence, not substituted for this final run.

| Gate | Actual result |
| --- | --- |
| Debug clean build and complete tests | **424 passed**: 387 unit + 37 UI; 0 failed, skipped or expected failures |
| Unsigned generic iPhone SDK Debug build | PASS |
| Normal unsigned Release build | PASS; `ENABLE_TESTABILITY = NO` |
| Separate Release isolation build/tests | **20 passed**: 9 unit + 11 UI; 0 failed, skipped or expected failures |
| Resource/binary inspections | PASS across Debug, device SDK, normal Release and Release-test products |
| Privacy inspection | No tracking/collected-data declarations; existing `35F9.1`, `CA92.1`, `C617.1` reasons preserved |
| Original current-main unit identities | **362/362** represented; missing identities `[]` |

The exact identity comparison is `baseline-regression-preservation.json`, using `baseline-unit-cases.json` and the fresh executed case tree—not merely a larger total. All historical Metal, synthetic geometry, storage and spatial-replay suites remain in the full run. The normal Release fixture flag is tested as ignored and cannot seed a synthetic closet or saved scan.

`CompactDark.xcresult` separately records **1 passed / 1 failed / 0 skipped** on iPhone SE (3rd generation), iOS 26.5, actual OS dark appearance. The normal journey passed. The largest-text failure occurred in `tryOn(waitForScene:)` before scene entry: the original driver repeatedly flung upward after skipping the action row. The original failed recording and UI snapshots are preserved in `CompactDarkEvidence`; no visibility, geometry, pixel, 44-point target or recovery assertion was removed to accommodate it.

The corrected driver subsequently passed both compact cases. After the final native button-padding adjustment, `CompactFinal.xcresult` was interrupted without a finalized `Info.plist`; its original test-host log records the largest-AX case passing in 90.525 s, then a long native idle-wait gap during the normal journey. The cause was not established, and no aggregate pass is claimed for that bundle. Only the owned compact simulator was shut down and booted—no erasure or security change. **`CompactFinalRecovered.xcresult` then completed 2 passed / 0 failed / 0 skipped / 0 expected failures** on the final UI implementation. It checks real cloth pixels, every rotation/reset control, visibility/reopening, scan-introduction dismissal and largest-AX targets at least 44 points. `CompactVerificationReceipt.json` retains the evidence chain.

The intervening `FinalVerification3` repeat passed **all 387 current unit cases**, but `FitCheckUITests-Runner` failed to initialize: **“Timed out while loading Accessibility.”** No UI case initialized in that attempt, and later build/isolation gates were not reached. Its original result and diagnostics remain in `FinalMatrixAccessibilityFailure.json` and `FinalMatrixAccessibilityDiagnostics`; it is not called a passing matrix or an app assertion failure. Fresh-simulator native UI preflight then passed, and **the unchanged complete `FinalVerification4` run passed every gate above**, preserving all tests, stores and security boundaries.

## Actual visual evidence and fallback

Finished evidence directory:

```text
/Users/anshbalusa/onyou-tryon-artifacts-20261107/FinalVisualEvidence
```

`screenshot-manifest.json` binds **19 primary running-app PNGs**, **14 compact OS-dark running-app PNGs** and **6 separately disclosed camera-chrome component PNGs** to original test attachments with matching SHA-256. Copies are unedited and unresized. `RenderedGeometryInspection.json` separately records all 20 final native renderer snapshots across four body/shirt pairs and five angles.

| View | File in `FinalVisualEvidence` |
| --- | --- |
| Saved synthetic textured avatar | `01-body-saved-synthetic-avatar.png` |
| Actual Closet and selected shirt | `02a-closet-selection.png`, `02-closet-selected-shirt.png` |
| Front / quarter / side / back | `03-shirt-front.png` through `06-shirt-back.png` |
| Visibility, restoration, reopening | `07-shirt-hidden.png`, `08-shirt-restored.png`, `09-shirt-reopened.png` |
| Clean return | `10-clean-return-to-body.png`, `18-return-after-scan-introduction.png` |
| Different garment and body/text size | `11-second-garment.png`, `12-second-body-accessibility.png` |
| Genuine prerequisite recovery | `13-missing-avatar-action.png` through `16-unusable-pose-recovery.png` |
| Actual scan introduction | `17-body-scan-introduction.png` |
| Frame / Body / Detail component guidance | `component-capture-finding.png`, `component-capture-body.png`, `component-capture-standard.png` |
| Final compact OS-dark / largest AX | `compact-dark/03-shirt-front.png`, `compact-dark/12-second-body-accessibility.png`; full 14-image journey in that directory |

Camera-chrome PNGs render shipping SwiftUI in the actual iOS test host against an authored camera-free backdrop. They are not physical camera footage, and they do not establish successful capture. The real scan introduction correctly reports unavailable hardware instead of faking a scan.

Backup video: **`onyou-tryon-demo-53s.mp4`**, independently reopened as 53.0 seconds, 1206×2622, 30 fps; actual extracted frames were inspected. Its unmodified simulator source is `raw-tryon-journey.mp4` (268.46 seconds). `video-provenance.json` and the video's `.metadata.json` list exact source ranges and hashes. The short version makes cuts to remove test setup/waits; retained segments remain 1× speed. It is not a navigation-latency or real-time performance claim, and no screenshot replaces the app's live geometry.

The video was captured from the earlier fully passing build before the last compact button-padding refinement. Geometry and journey behavior are unchanged; the 19 refreshed primary PNGs come from the exact final `FinalVerification4` build, and the 14 compact PNGs cover the final padding and largest-text behavior. Their distinct source receipts remain explicit in the manifests.

If graphical Simulator is unavailable, open that MP4 in the local video player and use the unedited PNGs as backup. On this host the native prebuilt helper also launched both with `--fixtures` and without opt-in arguments; the normal route showed **Example body**, no synthetic banner and no seeded closet.

Meeting explanation: “On You loads a saved textured avatar and the actual shirt record into one interactive native 3D scene. This demo uses clearly labeled authored inputs through the real storage and Closet contracts. Drape and the rear appearance are illustrative, not verified fit; real-device capture and reconstruction validation remain pending.”

## Changed-file ownership review

The reviewed publication inventory contains 33 modified existing files and 25 new paths: actual project metadata/verifier, native launch/profiling/fixture helpers, capture/Closet/try-on integration, bounded geometry and scene preparation, focused regressions, authored fixture assets/provenance and this handoff. Visual evidence and native diagnostic scaffolds remain outside Git.

No M1 measurement-avatar implementation, historical development view, Metal scene-session file or PR #25 branch was copied over or modified. The live post-implementation GitHub audit still showed `main` at `9b97ab387649a5da26ab01285c7957ae454b19c5` and PR #25 open/draft at `21e5728afbd0d2c1cfe367437ab796905537ddcb`, unchanged since `2026-11-06T22:08:11Z`. Only a new repair branch/draft PR is authorized for publication; no main or stacked-PR merge is part of this work.

## Review verdict

The saved-avatar → Closet → selected shirt → real native 3D try-on journey is implemented, rendered, visually inspected and freshly verified. Authored A/B bodies and Tide/Coral inputs are reproducible, isolated and explicitly synthetic. Rotation, reset, visibility, replacement, recovery and ownership transitions are exercised rather than inferred from titles.

This is a reviewable illustrative prototype—not production capture validation, a personal-body accuracy result or a physical-fit engine. The native sample-initialization limit and original simulator infrastructure failures remain documented with their evidence. No further segment, main merge or PR #25 change is included.
