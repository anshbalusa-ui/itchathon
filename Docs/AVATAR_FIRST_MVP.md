# FitCheck 2.0 — Avatar-first MVP

## Customer experience

1. Open FitCheck and create an avatar once.
2. Save the reusable avatar/profile on device (planned, not yet implemented).
3. Choose a garment from a sample catalog; later connect Ben's online products.
4. View an approximate garment visualization on the avatar.
5. Read simple per-region fit descriptions, with no body measurements, scores, or math shown to shoppers.

**The internal system still uses dimensions.** Hiding measurements must not be confused with validated accuracy. Do not call a virtual outfit an accurate fabric simulation or claim sizing certainty until independently tested.

## Task 1: automatic capture foundation — experimental

Branch: `feature/avatar-first-scanner-20261019`.

- New `Create your avatar` entry point on the existing home screen, without replacing existing demos.
- Camera capture with ARKit scene depth on LiDAR-supported iPhone Pro models.
- Vision human-pose detection and person segmentation.
- Automatic guided *front* then *side* capture after consecutive frames with a visible person, usable depth, and stable body-pose position.
- Two aligned capture snapshots (RGB pixel buffer, depth, confidence, segmentation mask, intrinsics, landmarks, timestamps) held **in memory only**.
- Deterministic capture-state tests including missing depth, unstable frames, cancellation and reset.

### Known limitations and safety gates

- This branch does **not** generate an avatar, measure body dimensions automatically, create clothing meshes, calculate garment fit, save a reusable profile, or integrate any store.
- The detector currently checks *scene-wide* depth validity, not whether each depth pixel is on the detected person; depth-to-person alignment and camera calibration are Task 2.
- The front/side stages are guided by text. The system does not prove the person is genuinely oriented front/side. Side-view joint occlusion may cause retries.
- Scene segmentation and a skeleton can make a scan *appear* plausible without providing accurate body shape. Do not substitute a generic avatar for confirmed scan-based geometry.
- Scanning should take place with ordinary clothing, in a private setting, with the person's consent; no one should feel pressured to scan.
- Rear-camera LiDAR ordinarily needs another person to hold the phone or an appropriate stand; self-serve capture is a future research task.
- No capture buffers are persisted or uploaded. They remain temporarily in memory and are released when leaving or retrying the screen. Future work must make deletion explicit for any persistent avatar data.

### Real-device test checklist

- Use a real LiDAR-capable iPhone Pro; confirm camera permission and ARKit scene depth support.
- Check that a person entirely in frame is detected and front then side capture progresses without manually selecting measurement points.
- Check that an empty room, cropped person, lost depth, or excessive movement cannot complete the scan.
- Confirm side view can succeed with partial landmark occlusion, and camera denial gives a useful message.
- Confirm a cancel/retry does not accidentally complete the old session and retained image buffers are released.
- Test multiple room backgrounds, lighting conditions and orientations (this first flow deliberately locks portrait).
- Verify no raw RGB image, person mask or depth map is written to persistent storage or transmitted.
- **No Mac/iPhone build or physical-device test was performed by the assistant.** Xcode verification is mandatory before merging.

## Avatar open-source shortlist

| Project | What to reuse | Licensing and constraint |
| --- | --- | --- |
| [MakeHuman](https://github.com/makehumancommunity/makehuman) | Base meshes and proportion variants to prototype the avatar offline | Core bundled assets CC0; application source AGPL. Verify any separately downloaded third-party assets individually. |
| [MPFB](https://github.com/makehumancommunity/mpfb2) | Blender-based authoring, clothing meshes and optional mesh conversion | Bundled graphical assets CC0; plugin source GPLv3. Do not embed plugin source into FitCheck without a separate legal assessment. |
| [Blender-to-RealityKit example](https://github.com/radcli14/blender-to-realitykit) | Reference workflow for GLB to USDZ and native RealityKit | Check any example asset/license before redistribution. |
| [SMPL-X](https://github.com/vchoutas/smplx) | Shape-model research reference | Main model/software typically limited to non-commercial scientific research; not a default commercial FitCheck dependency. |
| [IDM-VTON](https://github.com/yisol/IDM-VTON) | 2D image-generation research only | Code/checkpoints CC BY-NC-SA; does not estimate real garment fit and is not an iPhone-native 3D mesh. |

**Recommendation:** use licensed MakeHuman/MPFB CC0 assets exported for iOS, with a local RealityKit renderer in Task 3. Do not adopt a large 3D inference model to solve Task 1.

## Engineering sequence

- **Task 1:** prove reliable guided front/side RGB + LiDAR + Vision capture, without fake measurements.
- **Task 2:** align person mask to depth, estimate shape information with explicit confidence/retry logic, test repeatability and known measurement references *internally*.
- **Task 3:** export appropriately licensed parametric avatar mesh and render it on-device; only personalize dimensions the capture supports.
- **Task 4:** add sample store catalog and garment metadata; fit classifications must be independently calibrated and marked as estimates.
- **Task 5:** prepared garment presentation mesh, plain-language per-region fit feedback, and store integration interface.
- **Task 6:** remove legacy numeric flows from customer-facing UI, create/restore/delete avatar profile, test end to end.

## Verify locally

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project FitCheck.xcodeproj -scheme FitCheck -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test
```

Also build and test the scanning experience on a physical LiDAR iPhone. Simulator unit tests do not validate LiDAR or camera alignment.
