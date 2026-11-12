# On You — final release readiness

## Final status

**MVP software complete, physical validation pending.** The integrated offline journey is implemented and freshly verified. This is not a production-readiness, dimensional-accuracy, physical-fit or distribution-approval claim. No app publication, main merge, previous-PR closure or credential change was performed.

## Reviewed candidate and integration

- Repository: `anshbalusa-ui/itchathon`; customer-facing name **On You**. `FitCheck` remains the internal module/scheme.
- Refreshed `main`: `9b97ab387649a5da26ab01285c7957ae454b19c5`.
- Starting candidate: [draft PR #27](https://github.com/anshbalusa-ui/itchathon/pull/27), branch `integration/onyou-final-gap-audit-20261109`, commit `f84435a307922aab8e27eab47b27cfd90b58c9d7`.
- PR #25 head `21e5728afbd0d2c1cfe367437ab796905537ddcb` and PR #26 head `d204d77e3479f5500b75cf6803786da843ac8b45` are already ancestors of that candidate. Their implementations were reviewed, not cherry-picked or rebuilt. No newer remote implementation was found in the refreshed branch/open-PR inventory; the final refresh retained the same main/candidate heads.
- Focused [review branch](https://github.com/anshbalusa-ui/itchathon/tree/review/onyou-release-readiness-20261110): `review/onyou-release-readiness-20261110`, based on PR #27. Its draft review targets the integration branch so it contains only this readiness delta, not a duplicate application integration against main. Final commit and PR metadata are authoritative on that review branch.
- Verified source/test/project/asset/verifier SHA-256: `5d3963a6f10f9992caf70b3fa27e35c712e7883eb79f6c20d2d7b63834172770`. The full verifier confirmed these inputs remained unchanged throughout the run. Subsequent handoff changes are documentation only.

## Completed and left intact

- Native SceneKit body viewing, smooth measurement-driven generic body geometry, localized measurement input, cancel/save behavior, separate History, saved textured avatar loading and scan priority.
- Existing native Object Capture/Photogrammetry capture, two-pass/photo/depth admission, guidance, reconstruction preflight, texture/scale review, cancellation, retry and local save/load/delete software. Native success and accuracy still require physical validation.
- Local Closet, original garment-photo/measurement/pattern association, supported-shirt recognition/projection/consensus contracts, import, retake, reference selection and targeted deletion.
- Existing connected illustrative shirt shell on a saved avatar, observed front texture, explicitly inferred rear, scene preparation, actual visibility, rotation/reset, garment switching, dismissal/reopening, recovery and stale-work/lifecycle ownership.
- Debug-only authored fixtures and older Metal development labs, their admission/privacy boundaries and normal Release exclusion. The native On You app was not confused with the internal FitCheck demo.
- Existing storage formats, authorization checks, capture coverage, body/garment geometry, renderer engines and prior measured optimization. No new backend, cloth engine, account system, retailer service or asset dependency was introduced.

The prior audit remains historical integration evidence: [final gap audit](ONYOU_FINAL_GAP_AUDIT.md). There is no identified missing software feature blocking the defined offline MVP; the remaining validation/distribution gates are explicit below and in the checklist.

## Fixed during this pass

### Missing required-reason privacy declaration

`BodyCaptureModel.start()` already checks `.systemFreeSize` through `FileManager.attributesOfFileSystem` before capture writes and rejects less than 2,000,000,000 available bytes. The source and actual built Debug manifest omitted DiskSpace, and the existing checks omitted that API category as well.

- Added only `NSPrivacyAccessedAPICategoryDiskSpace` / `E174.1` to `Sources/Support/PrivacyInfo.xcprivacy`.
- Strengthened the existing `IntegrationPrivacyManifestTests` case and `Scripts/verify_development.py` four-bundle expectations. All previous reasons, duplicate-category checks, no-tracking and empty collected-data assertions remain.
- Reproduced before repair in `PrivacyRequiredReasonBefore.xcresult`: the new contract assertion failed because the actual bundled reason was `nil`, not `E174.1`. After repair, `PrivacyAndStorageAfter.xcresult` passed its 22 selected privacy, avatar, Closet and measurement-storage cases. The actual Debug app manifest was inspected again, then every final bundle was checked by the complete gate.
- No storage-space threshold, capture validation, data format, permission flow, networking or signing behavior changed. A local declaration check is not App Store acceptance.

Policy references: [Apple required-reason API declarations](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api) and [TN3183](https://developer.apple.com/documentation/technotes/tn3183-adding-required-reason-api-entries-to-your-privacy-manifest).

### Compact accessibility automation, not an app rewrite

The existing maximum-text measurement/History case exposed test-driver targeting problems on iPhone SE (3rd generation): edge/large swipes missed or overshot tall Body actions, reopening needed an explicit modal assertion, and a History swipe over its interactive 3D preview rotated the model instead of scrolling the list. The preserved recording showed the latter directly. A collection container's own tap-hittability also incorrectly excluded a valid list gesture.

`UITests/TryOnUITests.swift` now uses controlled interior Body swipes, waits/asserts that the reopened editor exists, and scrolls the native list gutter. Every existing pixel/data/touch-target assertion and test identity is retained; no threshold, input size or tested path was reduced. The full original compact journey passed in `CompactNativeListScroll.xcresult`, including actual changed body pixels, cancellation/reopening, History and refusal to treat manual geometry as a captured scan. The entire suite subsequently passed on iPhone 17.

No corresponding Body/History/settings/try-on product defect was established, so those implementations were left unchanged. The existing About mesh setting was also exercised against actual changed/restored model pixels; its initial throwaway row-tap error was corrected in the driver, not hidden by an app change. Investigation scaffolds were removed before final verification.

### Contradictory documentation

Corrected historical statements that native try-on was unimplemented, that current verification still used obsolete project metadata, and that native capture required entering barefoot height. Current capture retains depth-derived scale; its recorded height comes from the reconstructed bounds and is not independent metrology. Documentation also distinguishes attempted/best-effort raw-input cleanup from verified erasure under device lock or I/O failure.

## Fresh software verification

Environment: Xcode 26.5, XcodeGen 2.46, Intel x86_64 host, iOS 26.5 iPhone 17 simulator. Compact boundary proof used the existing iPhone SE (3rd generation) simulator. Only owned validation simulators were booted/shut down; no simulator was erased and teammate simulators/data were left untouched.

| Final complete gate | Observed result |
|---|---|
| Clean Debug build and full unit/UI suite | **439 passed: 399 unit + 40 UI; 0 failed, 0 skipped, 0 expected failures** |
| Release isolation suite | **21 passed: 9 unit + 12 UI; 0 failed, 0 skipped, 0 expected failures** |
| Generic unsigned iPhone SDK Debug build | **PASS**; compilation only, not a phone installation/capture test |
| Normal Release build | **PASS**, `ENABLE_TESTABILITY=NO` |
| Debug, iPhone, normal Release and Release-test resources/privacy | **PASS**; all four required-reason categories present; pinned production human assets/notices retained |
| Release development boundary | **PASS**; no development resource leaks, packaged runtime synthetic artifacts/replays or normal-Release development markers |
| Exact prior regression identities | **PASS**; all 439 prior Debug and 21 prior Release identities retained, no missing/added identities, no deleted/skipped cases |
| Physical camera/LiDAR/fit/distribution verification | **NOT RUN** |

Fresh complete receipt, logs, result bundles and inspected build products:

`/Users/anshbalusa/onyou-release-readiness-artifacts-20261110/FinalVerification/verification-yk_mca89/verification.json`

The same directory contains `DebugTests.xcresult`, `ReleaseTests.xcresult`, `iPhoneBuild.xcresult`, `ReleaseBuild.xcresult` and command logs. Exact case-by-case retention is recorded at:

`/Users/anshbalusa/onyou-release-readiness-artifacts-20261110/FinalRegressionInventoryRetention.json`

The original failed metadata assertion and intermediate UI-driver failures remain outside Git. They are not counted as successful runs, suppressed with expected failures or substituted for the final receipts. There was no environmental test failure in the complete final gate. A resumed simulator screenshot command timed out before the owned compact simulator was booted; normal non-erasing boot restored that diagnostic workflow. Hardware unavailability is a validation limitation, not a fabricated product failure or pass.

## Actual visual review and evidence

Evidence root: `/Users/anshbalusa/onyou-release-readiness-artifacts-20261110/`. Paths below are relative to that root; PNGs are unedited images from the running app. `FinalNativeUIEvidence/manifest.json` binds final test names and attachments.

| Actual final app surface | PNG |
|---|---|
| Saved synthetic avatar wearing Tide shirt, front | `FinalNativeUIEvidence/33BD0AF3-A3EC-410D-A736-316191DD0F86.png` |
| Side after rotation | `FinalNativeUIEvidence/367A1E53-D220-4C3D-8D97-7948C3E9FC8C.png` |
| Back / inferred rear material | `FinalNativeUIEvidence/7CF9DCE7-5FC1-4E1B-93A8-257D731C283A.png` |
| Changed garment, Coral shirt | `FinalNativeUIEvidence/570955F2-8DD4-4B1D-9710-61EA1E6142DE.png` |
| Distinct body B at largest accessibility text | `FinalNativeUIEvidence/EA411C52-C2AD-49E8-86DA-C4659096B22B.png` |
| Native numeric measurement editor | `FinalNativeUIEvidence/186256B0-CBF6-4C5B-8175-C13667899004.png` |
| Saved manual body / History | `FinalNativeUIEvidence/B8C1F6D7-4E7A-4F62-8B71-292E17EDC11E.png`, `FinalNativeUIEvidence/F248279D-6877-4C41-8932-E56C15963B5A.png` |
| Clean return to Body | `FinalNativeUIEvidence/F7545CA9-4C86-4176-85AB-1A9668A19513.png` |
| Compact maximum-text editor / History / scan-required recovery | `CompactFinalEvidence/AFB692CB-9441-4FEF-8E31-84E064C1BF68.png`, `4967DF04-4003-4C31-B8C5-C4B8AF64E282.png`, `11181A11-3191-4A23-872E-08453A4470C4.png` in the same directory |

The actual system appearance was explicitly switched for dark review, not inferred from a launch-argument label. Dark native try-on is in `DarkUIEvidenceBefore/C6EC0430-8C65-4695-A44C-CD1B8700F887.png`; About/guide/actual wireframe/restoration are indexed by `DarkSettingsEvidence/manifest.json`. These unchanged app surfaces were reviewed before the final metadata-only production change; primary appearance was restored to light.

Existing native benchmark probes also rendered body A/B × Tide/Coral × front/quarter/left/right/back: 20 actual offscreen SceneKit frames per run, twice. All pair/angle images were inspected; no missing garment, detached sleeve, blank scene or reproduced penetration defect justified replacing the shell. Minor angular seam/trim shading and the plain inferred rear remain illustrative limitations. Offscreen frames and camera-chrome hosting snapshots are not physical capture footage. The latter use an explicit stand-in background and are not presented as camera success.

No new edited demo recording is claimed. The previously reviewed meeting backup recording remains documented in README; screenshots/recordings/build evidence stay outside Git.

## Measured performance — preserve existing implementation

Two serialized runs of the existing native benchmark on the same simulator/unchanged rendering and geometry code. These are actual initial/repeat measurements, **not an optimization before/after claim**. Geometry checksums/vertex counts were unchanged. Means below use four body/shirt pairs for scene stages, three predictions, two warm detector calls and sixteen nonfront snapshots per run as applicable.

| Workload | Unit | Initial | Repeat |
|---|---|---:|---:|
| Cold complete try-on builder | ms | 5902.19 | 5975.10 |
| Cold builder range | ms | 5449.59–6261.14 | 5067.07–6967.21 |
| Avatar loading | ms | 21.39 | 24.77 |
| Photo loading/normalization | ms | 1.83 | 2.00 |
| Surface extraction | ms | 39.79 | 39.83 |
| Pose estimation | ms | 560.58 | 646.09 |
| Authored pattern revalidation | ms | 186.42 | 184.96 |
| Actual garment mesh preparation | ms | 4856.53 | 4853.30 |
| Prepared scene initialization | ms | 234.14 | 222.14 |
| Same-builder warm reuse | ms | 5.14 | 8.00 |
| Cold builder plus first offscreen frame | ms | 5973.34 | 6028.87 |
| Warm reuse plus first offscreen frame | ms | 31.18 | 41.13 |
| Nonfront offscreen snapshot | ms | 17.31 | 20.47 |
| Native Core ML model initialization | ms | 4564.13 | 4234.01 |
| Native landmark prediction | ms | 2832.60 | 2891.00 |
| Warm complete landmark detection | ms | 2859.13 | 2888.86 |
| Warm 101-section geometry workload | ms | 266.64 | 289.29 |
| Process-lifetime peak resident memory | MiB | 507.76 | 506.66 |
| First unsupported native preflight rejection | ms | 26.20 | 33.15 |

| Actual UI presentation observation | Tap-to-observed-shirt-pixel upper bound (ms) |
|---|---:|
| First open | 12664.85 |
| New presentation after closing | 11023.79 |

- Mesh preparation remains the dominant repeatable simulator cost. Existing staged, asynchronous, cancellable loading remains in place; no scan coverage, fidelity, model, integrity or ownership boundary was reduced to create a speedup.
- Same-builder reuse is not closing/reopening: close clears owned scene/cache state. UI observation bounds include XCTest interaction/idle/screenshot overhead and are not app-only navigation latency.
- Pattern revalidation uses authored retained points; it is not the separate live model prediction. Simulator model inference uses CPU; these numbers are not phone/Neural Engine performance.
- Snapshot timings are not interactive FPS. Peak RSS includes earlier inference/framework work and is neither retained heap nor evidence of a leak. Device memory/thermal/render responsiveness remains a separate gate.
- Native reconstruction rejected as unsupported before depth admission in every probe; warmed rejections were submillisecond. These rejection timings do not measure capture or reconstruction speed. Actual camera setup, Apple's reconstruction time and hardware performance are NOT RUN.
- The previous PR #26 warm geometry optimization is retained. Its retired implementation was not rebuilt and no new credit for that historical optimization is claimed. Profiling the current cold mesh on representative hardware is preferable to speculative cache/fidelity changes.

Raw receipts: `CurrentCandidatePerformance/Performance.xcresult`, `CurrentCandidatePerformanceRepeat/Performance.xcresult`, their `attachments/manifest.json` files, `ReadinessPerformanceComparison.json` and `PerformanceFindings.md` under the evidence root.

## Privacy, storage and hardware boundaries

Scan model/manifest and Closet image/manifest writes explicitly use complete file protection; their storage directories are explicitly backup-excluded. Avatar loading verifies SHA-256 and rejects malformed/symlink/nonregular input. Scanned garment pattern evidence is image-bound where present; imported/photo-only garments do not acquire a new universal content-hash guarantee. Normal persistence, corruption, association, deletion isolation and lifecycle tests pass; no storage format or migration was changed.

Manual measurements/history are separate local UserDefaults data (`on-you.measurements.v1`), not captured scans. They have no established explicit scan/photo backup-exclusion/protection guarantee. Device lock/backup behavior, fault-injected save/unlink/termination behavior and deletion/retention policy still need review. Source-identified best-effort cleanup/partial-delete/orphan boundaries are documented in the [release checklist](ONYOU_RELEASE_CHECKLIST.md), not misreported as reproduced hardware defects or silently “fixed” with a policy rewrite.

Static native source review found no app-managed upload client. Explicit user-tapped product/license/Settings links are distinct from uploads; this does not certify all OS/SDK network or platform-backup behavior. Camera permission is requested on deliberate capture entry and has denial/recovery handling. Permission prompts, lock-state protection and real capture interruption are not physically validated by simulator tests.

Fresh `devicectl`/`xctrace` discovery, including the final readiness refresh, found the paired phone unavailable/offline and no usable physical target. Suitable positioned nonpersonal physical assets were not available through the tooling. **All 16 body and 10 shirt physical cases remain NOT RUN**. Raw device identifiers stay outside Git. No private scans were requested and no generated fixture was presented as a personal capture.

Complete reproducible procedures, instrumentation, observations and pass/fail criteria: [device validation](ONYOU_DEVICE_VALIDATION.md). Independent body/shirt metrology, repeats, textile thickness/stretch, drape, motion, clearance, constructions and claims requirements: [fit validation roadmap](ONYOU_FIT_VALIDATION_ROADMAP.md). Geometry spacing is not measured pressure or accurate clothing size; a generic model from five dimensions is not a unique reconstruction of a person.

## Remaining release gates and product scope

The actionable [release acceptance checklist](ONYOU_RELEASE_CHECKLIST.md) covers compatible hardware/OS, permission behavior, real capture, storage/backup/deletion fault boundaries, VoiceOver/advertised orientations, device memory/stability, privacy/legal disclosures and authorized signing/archive/distribution approval. These are outstanding gates, not permission to call this production-ready. No signed archive, TestFlight/App Store upload or physical-fit approval was performed.

The offline MVP does not require accounts, a backend, live retailer inventory/feeds, synchronization, app-managed cloud backup, checkout or more garment categories. Existing manually supplied **View product** links are preserved, not a retailer integration. The [post-MVP roadmap](ONYOU_POST_MVP_ROADMAP.md) records each unapproved later integration and its real dependencies. No commercial data, measurements, prices or physical accuracy were invented.

## Reproducible launch

On macOS with Xcode and XcodeGen:

```sh
Scripts/launch_onyou.sh --fixtures
```

This builds/boots/installs the real Debug app with disclosed authored data in isolated temporary stores, without signing credentials or simulator erasure. Use `--body b` for the second body, or omit `--fixtures` for normal On You. Body → Closet → Fixture · Tide shirt → Try on → rotate/reset/hide/show → close → select Coral → Try on → return demonstrates the saved-avatar workflow without a camera. Manual illustration remains a separate Body/Measurements/History path when no captured avatar is selected.

The exact final Debug product was also launched successfully with the existing helper:

```sh
Scripts/launch_onyou.sh --fixtures \
  --simulator 354553A7-2CE9-4FF6-B196-D9CC74C10712 \
  --app '/Users/anshbalusa/onyou-release-readiness-artifacts-20261110/FinalVerification/verification-yk_mca89/DebugDerived/Build/Products/Debug-iphonesimulator/On You.app'
```

Meeting explanation: **On You already demonstrates measurement-driven generic bodies, local saved avatars and interactive illustrative shirt-on-avatar rendering. Native scanning software is integrated, but real-device capture, dimensional accuracy and physical garment fit still require independent validation.**
