# On You

An offline iPhone tool for capturing textured body scans, exploring measurement-based body models, and illustrating scanned shirts on saved avatars.

## Run

```sh
bitrig preview -platform iOS
```

`Project.json` is the build configuration. The app is named **On You**; its internal Swift module remains `FitCheck` for compatibility with the imported tests.

For the native Xcode simulator workflow (macOS, Xcode and XcodeGen):

```sh
Scripts/launch_onyou.sh
Scripts/launch_onyou.sh --fixtures
```

The first command opens the normal app. The second opens the **same Body/Closet/try-on screens** with disclosed authored data in isolated temporary stores. Neither command erases simulators or requires signing credentials. Use `--simulator UDID` to choose a particular iPhone; `--body b` with `--fixtures` selects the wider/taller second body.

## Measurement-driven avatar demo (M1, Debug only)

The reviewed M1 work is integrated alongside the native On You app; no branch switch is needed.

```sh
Scripts/launch_friday_demo.sh
```

In **FitCheck Demo Showcase**, tap **Create avatar**. Enter height, chest/waist/hip circumferences and shoulder width in **cm**, or choose fictional **Sample A / Sample B**, then **Generate avatar**. Drag or use Left / Right / Reset; show the illustrative shirt, or choose **Edit measurements** to generate another shape. The internal hub also has **Measurement avatar demo**.

These values change actual smooth human mesh geometry in native Metal, not a label or image. This internal lab is a non-persistent generic illustration: it is not a personal scan, validated fit or size recommendation. Its shirt uses the same illustrative deformation without a fit/pressure map. Normal On You scanning, its saved-avatar try-on and the separate manual measurement store retain their existing boundaries.

The helper builds unsigned Debug using `Project.json`, rejects Release/device/older builds without the measurement demo and pinned assets, and never erases simulator data. Use `--simulator UDID` or `--app "/absolute/path/to/Debug-iphonesimulator/On You.app"`. See the [M1 evidence and limitations](Docs/FRIDAY_DEMO_D1_HANDOFF.md) and [final integration audit](Docs/ONYOU_FINAL_GAP_AUDIT.md).

## Screens

- **Body:** a gesture-only viewer. Drag to orbit and pinch to zoom. A saved scan takes priority over the manual measurement model.
- **Scan:** prop iPhone securely, tap **Start scan**, then step into view during the countdown. Capture waits for fresh whole-body framing; keep iPhone fixed and turn slowly in place. Spoken cues report collected/missing views, and sufficient usable coverage moves to processing automatically.
- **Closet:** scan a flat shirt with its collar at the top and both sleeves visible; review its image and depth-backed dimensions, then save or retake. Imported photographs remain photo-only.
- **Try on:** open a saved shirt's detail page and choose **Try on**. A saved textured avatar and a metric shirt scan are required. Rotate/inspect front and back, reset the camera, or hide/show the actual garment mesh. Missing prerequisites offer scan/retake recovery rather than a successful bare-avatar preview.
- **Measurements:** on the example/manual **Body** screen, choose **Measurements** to enter height, chest, waist, hips, and shoulder width in centimeters or inches. The existing preview updates while editing; Cancel discards the draft, and Save updates the separate manual model and History. This illustration does not create a captured scan or authorize saved-scan try-on; captured geometry retains its own height calibration.
- **History:** inspect saved bodies, compare dimensions with the current body, restore a version, or delete a record without changing the current body.
- **How to measure:** instructions for each dimension.
- **About:** mesh display option, model source, and local data information.

Measurements and history use the separate `on-you.measurements.v1` local storage namespace. Existing FitCheck records are untouched. No account, server, runtime model download, or added package is required.

## Body scans

On supported LiDAR iPhones, set iPhone upright on a secure surface with the rear camera facing you. Tap **Start scan**, step into view during the five-second countdown and face the camera with arms slightly away. Capture starts only after the countdown and fresh automatic framing/calibration; no numerical input or helper is required. Keep iPhone fixed and turn slowly in place. **Cancel start**, help or an inactive app cancels pending arming; accepted photos are not reset by an ordinary pause. Choosing **Capture missing views** arms recovery directly, retaining the admitted views rather than asking for another Start tap or an automatic second full turn.

Find **Scan help** in the system toolbar’s options menu. The dark viewfinder keeps its size as instructions change, and **Start scan** stays outside scrolling guidance at larger text sizes. A smooth body guide fades into curved framing marks during capture. An AR halo is locked around the calibrated person: its yellow segments represent saved angular views, and a white marker identifies a missing angle. These are custom SceneKit guides in the existing ARKit session, not Apple’s moving-camera Object Capture workflow. Invalid, stale, and paused tracking hides the spatial guide. Reduce Motion disables decorative transitions. In review, **Retake** and **Use this scan** stay in the bottom safe area, with accessible rotation, zoom, and reset actions on the actual scan.

One ARKit session supplies the preview and matching RGB and LiDAR frames. Vision estimates the person's turning angle and masks the background. `PhotogrammetrySession` reads matched photos, person masks, and confidence-filtered depth lazily. It reconstructs a textured USDZ on iPhone.

Reconstruction requires at least 60 distinct-angle images, 32 of 36 angular sectors, no gap over 20 degrees, and three confidently framed front-region photos. The same floors are checked again using the actual native reconstructed viewpoints, excluding rejected inputs and poses inconsistent with the captured yaw. The same admitted IDs feed final input validation and missing-view recovery; a small median alignment error alone cannot let outliers count as valid coverage. Missing textures, invalid dimensions or a height scale correction outside 0.9–1.1 reject the result. Drag and pinch the actual textured result to inspect it. **Use this scan** replaces the saved avatar; **Retake** or closing keeps the previous one.

Body and shirt capture share graded Core Haptics and a red edge vignette. **Scan options → Guidance haptics** controls vibration and completion feedback. Distance warnings begin outside ±18% of the calibrated target and recover inside ±12%; aiming and roll use 12°/8° margins. Safe, paused, stale, backgrounded or disabled guidance stops vibration. Shirt capture calibrates its own fixed distance, tracks the stationary flat shirt through live camera poses, and encodes the cutout only after three measurements agree.

Body **Scan options → Spoken guidance** controls local Apple text-to-speech for setup, countdown, view milestones, missing views, processing and review. VoiceOver uses accessibility announcements instead of a competing synthesizer. Speech stops for help/discard, inactive scenes and dismissal, and keeps only the latest pending instruction. There is no microphone recording, voice-command engine or external service. If head-to-foot framing with usable depth cannot fit in the available space, reposition iPhone or retry in a clearer area; no partial/template avatar is substituted.

New captures use captured depth for metric scale; older height-calibrated scans retain their saved scale. Neither establishes chest/waist accuracy or facial fidelity. A person must hold their pose; motion and loose clothing can compromise reconstruction. Hardware accuracy, repeatability, and likeness have **not** been validated in this workspace. Apple documents the [static-subject and overlapping-photo requirements](https://developer.apple.com/documentation/realitykit/capturing-photographs-for-realitykit-object-capture).

Scans live in a separate file-protected, backup-excluded Application Support directory. SHA-256 admission checks the saved model before loading. New-model installation writes the active record atomically, preserving the previous scan on failure. Raw photos/checkpoints are removed after successful reconstruction; canceled or abandoned capture work is cleaned separately. The simulator lacks LiDAR and presents an honest unsupported-device state, with no synthetic scan-success path.

## Illustrative shirt draping

The main try-on path uses native **SceneKit**, the actual saved USDZ, the exact shirt image, and admitted garment observations. A continuous surface-aware shell joins the torso, shoulders and sleeves with open neckline, cuffs and hem. The front uses the observed shirt image; the plain rear is explicitly inferred. Pose references come from supported standing mesh geometry, not a required face-detection request. Unsupported surfaces reject without a generic-body substitute.

This is **not verified physical fit, tension or pressure**. A textured scan includes the clothing worn during capture and cannot establish hidden anatomy or fabric behavior. No separate face-photo collection is implemented.

Try-on adds an interruptible one-shot settling animation without rebuilding the garment mesh. Orbit preserves zoom and elevation; Reduce Motion removes settling and camera inertia. The detail screen retains its bounded preparation cache between preview openings. This animation does not simulate cloth physics.

The Debug-only fixture route supplies authored Tide/Coral shirts and two genuinely different body geometries through the real local save/load contracts. It does not prove camera recognition or reconstruction and never marks a personal scan complete. Normal Release excludes this route and its artifacts. Fixture provenance: [`DevelopmentAssets/OnYouTryOnFixtures/PROVENANCE.json`](DevelopmentAssets/OnYouTryOnFixtures/PROVENANCE.json).

Current implementation, exact evidence, limitations and review status: [`Docs/TRYON_DRAPING_SCAN_PERFORMANCE_HANDOFF.md`](Docs/TRYON_DRAPING_SCAN_PERFORMANCE_HANDOFF.md). Older internal FitCheck Metal demos remain separate from this On You workflow.

Simulator backup materials stay outside Git at `/Users/anshbalusa/onyou-tryon-artifacts-20261107/FinalVisualEvidence`: `onyou-tryon-demo-53s.mp4`, unedited journey PNGs, `compact-dark/` captures and hash/provenance manifests. The video is actual app footage with waits cut, not a real-time performance claim. If graphical Simulator is unavailable, use that verified recording and the PNGs.

## Manual model

The bundled anatomical mesh comes from [MakeHuman](https://github.com/makehumancommunity/makehuman), under CC0. Original provenance and licenses remain in `DevelopmentAssets/HumanShowcase/`. Chest, waist, and hip scale factors come from convex cross-sections of the actual base mesh. Smooth regional deformation changes vertex positions; normals are rebuilt for the new surface. Height and shoulder width also affect geometry. SceneKit supplies native rendering, lighting, orbit, and zoom.

This is an approximate body shape from five dimensions. It does not uniquely reconstruct a person or simulate clothing fit. Shoulders use an approximate anatomical reference; unentered proportions are estimated.

[humanoid-kit](https://github.com/jbcom/humanoid-kit) was also reviewed: its web runtime and large morph system were unnecessary for this native MVP. No humanoid-kit software was copied. We reused the CC0 MakeHuman mesh already supplied by the requested itchathon repository.

## Verification

**Stationary-scan refinement:** [`Docs/ONYOU_STATIONARY_SCAN_REFINEMENT.md`](Docs/ONYOU_STATIONARY_SCAN_REFINEMENT.md) records the current source audit, targeted fixes, compile/isolated-logic observations and deferred validation. No XCTest suites, simulator/device journeys, body scans or benchmarks were run for that assignment. Historical results below do not validate the newer rotating-person scanner or this refinement.

`Tests/AvatarScanTests.swift` checks scale admission, minimum coverage, textured USDZ persistence, failed-save preservation, corruption rejection, and deletion isolation. Its textured box is a synthetic fixture, not a human scan.

`Tests/OnYouTests.swift` checks section dimensions, height, normals, invalid inputs, extreme values, history, persistence, and corrupted-storage handling. `UITests/OnYouUITests.swift` checks the clean viewer, scan setup/cancellation and Closet's automatic-capture route. The focused `TryOn…Tests` cover actual saved geometry, surface clearance, UV/index validation, rendered garment pixels, stale-work cancellation, retakes, rapid navigation, backgrounding, recovery and largest-text controls.

The previous ARKit revision built signed for iPhoneOS and launched on an iPhone 17 Pro Max. Its host assertions passed for guidance, calibration and distributed input coverage. The device disconnected before that revision's device tests could start. Receipts are under `/private/tmp/onyou-device-fix-1mmMjj/GuidanceEvidence/`.

Completed human reconstruction, vibration strength and live shirt recognition still require hands-on testing. Authored try-on fixtures do not validate these. Retakes require explicit Save after review; Cancel preserves the saved shirt.

The imported project documented Bitrig rejecting `test` for standard `Project.json` projects (exit 78). The current native build/test workflow uses XcodeGen and Xcode directly; it does not require Bitrig.

The current native verification entry reads **`Project.json`**, generates `On You.xcodeproj`, and exercises scheme `FitCheck` with the real `On You.app` product:

```sh
/usr/bin/python3 Scripts/verify_development.py --simulator UDID --output-root NEW_EVIDENCE_DIRECTORY
```

It includes Debug unit/UI, unsigned iPhone-SDK compilation, normal Release, Release isolation and resource/privacy inspection. Test execution uses a noninteractive launcher; no debugger permission is required. `Scripts/benchmark_onyou.sh --help` describes the separate opt-in cold/warm native benchmark. Do not substitute results from PR #25 or the older standalone FitCheck project.

**Historical integrated verification (PR #25 / PR #26, before the newer scanner):** the complete `Scripts/verify_development.py` matrix passed on that combined implementation, including its native measurement editor, rendered geometry, lifecycle/persistence regressions, unsigned iPhone SDK build, normal Release and resource/privacy isolation. See [the historical final gap audit](Docs/ONYOU_FINAL_GAP_AUDIT.md) for its exact totals, source fingerprint, screenshots and remaining hardware validation. Those results are not evidence that the latest stationary full-body capture/reconstruction works.

Historical teammate verification on November 6, 2026: nine unit tests and two UI tests passed on the iPhone 17 simulator. The UI tests cover clean viewer controls, scan preparation/cancellation, and manual entry/save/history. Bitrig builds passed for iOS Simulator Debug and physical-iPhone Release. Rendered screens were checked in the Bitrig iPhone preview. These results predate the try-on repair; a real person's capture/reconstruction and measurement accuracy remain untested.

## Upstream

Imported from [anshbalusa-ui/itchathon](https://github.com/anshbalusa-ui/itchathon), commit `40feaf4931614637c3e1dc05407af2660eb56f19`. The [upstream README](Docs/UPSTREAM_README.md) and original development labs remain for reference. Debug-only `-fitcheck-…` launch flags retain their original internal routes; normal Debug and Release launch On You.
