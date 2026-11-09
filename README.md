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

## Screens

- **Body:** a gesture-only viewer. Drag to orbit and pinch to zoom. A saved scan takes priority over the manual measurement model.
- **Scan:** guided LiDAR/photo capture, reconstruction, scale review, and scan deletion. A helper circles a still person twice; at least 60 input images and two completed passes are required.
- **Closet:** scan a flat shirt with its collar at the top and both sleeves visible; review its image and depth-backed dimensions, then save or retake. Imported photographs remain photo-only.
- **Try on:** open a saved shirt's detail page and choose **Try on**. A saved textured avatar and a metric shirt scan are required. Rotate/inspect front and back, reset the camera, or hide/show the actual garment mesh. Missing prerequisites offer scan/retake recovery rather than a successful bare-avatar preview.
- **Measurements:** enter height, chest, waist, hips, and shoulder width in centimeters or inches. The preview updates while editing. Save updates the manual model; captured geometry keeps its own height calibration.
- **History:** inspect saved bodies, compare dimensions with the current body, restore a version, or delete a record without changing the current body.
- **How to measure:** instructions for each dimension.
- **About:** mesh display option, model source, and local data information.

Measurements and history use the separate `on-you.measurements.v1` local storage namespace. Existing FitCheck records are untouched. No account, server, runtime model download, or added package is required.

## Body scans

On supported LiDAR iPhones, `ObjectCaptureSession` gathers photos and depth through Apple's native guided-capture UI. `PhotogrammetrySession` reconstructs a textured USDZ using its supported iOS `.reduced` detail level, object masking, high feature sensitivity, and the captured checkpoint data. Skin, face, hair, and clothing come from the photographs. This is captured surface geometry; it is not an inferred unclothed body or a rigged character.

Two completed circles and at least 60 images are required. Invalid/skipped inputs reduce the admitted image count. Tracking problems, incomplete stitching, missing textures, invalid dimensions, or a height scale correction outside 0.9–1.1 reject the result. USDZ coordinates are converted to meters and Y-up. The user reviews the textured reconstruction and confirms it before it replaces an existing scan.

Actual barefoot height calibrates uniform scale. Matching that single reference does not establish chest/waist accuracy or facial fidelity. A person must hold their pose; motion and loose clothing can compromise reconstruction. Hardware accuracy, repeatability, and likeness have **not** been validated in this workspace. Apple documents the [static-subject and overlapping-photo requirements](https://developer.apple.com/documentation/realitykit/capturing-photographs-for-realitykit-object-capture).

Scans live in a separate file-protected, backup-excluded Application Support directory. SHA-256 admission checks the saved model before loading. New-model installation writes the active record atomically, preserving the previous scan on failure. Raw photos/checkpoints are removed after successful reconstruction; canceled or abandoned capture work is cleaned separately. The simulator lacks LiDAR and presents an honest unsupported-device state, with no synthetic scan-success path.

## Illustrative shirt draping

The main try-on path uses native **SceneKit**, the actual saved USDZ, the exact shirt image, and admitted garment observations. A continuous surface-aware shell joins the torso, shoulders and sleeves with open neckline, cuffs and hem. The front uses the observed shirt image; the plain rear is explicitly inferred. Pose references come from supported standing mesh geometry, not a required face-detection request. Unsupported surfaces reject without a generic-body substitute.

This is **not verified physical fit, tension or pressure**. A textured scan includes the clothing worn during capture and cannot establish hidden anatomy or fabric behavior. No separate face-photo collection is implemented.

The Debug-only fixture route supplies authored Tide/Coral shirts and two genuinely different body geometries through the real local save/load contracts. It does not prove camera recognition or reconstruction and never marks a personal scan complete. Normal Release excludes this route and its artifacts. Fixture provenance: [`DevelopmentAssets/OnYouTryOnFixtures/PROVENANCE.json`](DevelopmentAssets/OnYouTryOnFixtures/PROVENANCE.json).

Current implementation, exact evidence, limitations and review status: [`Docs/TRYON_DRAPING_SCAN_PERFORMANCE_HANDOFF.md`](Docs/TRYON_DRAPING_SCAN_PERFORMANCE_HANDOFF.md). Older internal FitCheck Metal demos remain separate from this On You workflow.

Simulator backup materials stay outside Git at `/Users/anshbalusa/onyou-tryon-artifacts-20261107/FinalVisualEvidence`: `onyou-tryon-demo-53s.mp4`, unedited journey PNGs, `compact-dark/` captures and hash/provenance manifests. The video is actual app footage with waits cut, not a real-time performance claim. If graphical Simulator is unavailable, use that verified recording and the PNGs.

## Manual model

The bundled anatomical mesh comes from [MakeHuman](https://github.com/makehumancommunity/makehuman), under CC0. Original provenance and licenses remain in `DevelopmentAssets/HumanShowcase/`. Chest, waist, and hip scale factors come from convex cross-sections of the actual base mesh. Smooth regional deformation changes vertex positions; normals are rebuilt for the new surface. Height and shoulder width also affect geometry. SceneKit supplies native rendering, lighting, orbit, and zoom.

This is an approximate body shape from five dimensions. It does not uniquely reconstruct a person or simulate clothing fit. Shoulders use an approximate anatomical reference; unentered proportions are estimated.

[humanoid-kit](https://github.com/jbcom/humanoid-kit) was also reviewed: its web runtime and large morph system were unnecessary for this native MVP. No humanoid-kit software was copied. We reused the CC0 MakeHuman mesh already supplied by the requested itchathon repository.

## Verification

`Tests/AvatarScanTests.swift` checks scale admission, minimum coverage, textured USDZ persistence, failed-save preservation, corruption rejection, and deletion isolation. Its textured box is a synthetic fixture, not a human scan.

`Tests/OnYouTests.swift` checks section dimensions, height, normals, invalid inputs, extreme values, history, persistence, and corrupted-storage handling. `UITests/OnYouUITests.swift` checks the clean viewer, scan setup/cancellation and Closet's automatic-capture route. The focused `TryOn…Tests` cover actual saved geometry, surface clearance, UV/index validation, rendered garment pixels, stale-work cancellation, retakes, rapid navigation, backgrounding, recovery and largest-text controls.

The imported project documented Bitrig rejecting `test` for standard `Project.json` projects (exit 78). The current native build/test workflow uses XcodeGen and Xcode directly; it does not require Bitrig.

The current native verification entry reads **`Project.json`**, generates `On You.xcodeproj`, and exercises scheme `FitCheck` with the real `On You.app` product:

```sh
/usr/bin/python3 Scripts/verify_development.py --simulator UDID --output-root NEW_EVIDENCE_DIRECTORY
```

It includes Debug unit/UI, unsigned iPhone-SDK compilation, normal Release, Release isolation and resource/privacy inspection. Test execution uses a noninteractive launcher; no debugger permission is required. `Scripts/benchmark_onyou.sh --help` describes the separate opt-in cold/warm native benchmark. Do not substitute results from PR #25 or the older standalone FitCheck project.

Historical teammate verification on November 6, 2026: nine unit tests and two UI tests passed on the iPhone 17 simulator. The UI tests cover clean viewer controls, scan preparation/cancellation, and manual entry/save/history. Bitrig builds passed for iOS Simulator Debug and physical-iPhone Release. Rendered screens were checked in the Bitrig iPhone preview. These results predate the try-on repair; a real person's capture/reconstruction and measurement accuracy remain untested.

## Upstream

Imported from [anshbalusa-ui/itchathon](https://github.com/anshbalusa-ui/itchathon), commit `40feaf4931614637c3e1dc05407af2660eb56f19`. The [upstream README](Docs/UPSTREAM_README.md) and original development labs remain for reference. Debug-only `-fitcheck-…` launch flags retain their original internal routes; normal Debug and Release launch On You.
