# On You — foundation consolidation

**Source audit and selective integration, 2026-11-22.** This report distinguishes code existence, branch adoption and verification. It does not claim successful personal scanning, exact dimensions, physically simulated fabric or production readiness. Product: **On You**; existing native module/scheme: **FitCheck**.

## 1. Fresh GitHub state and work protection

Fetched origin again and queried all PR states before source changes. Verified starting `origin/main`:

**`b3e0397eb6ac1ce8ab13b84e00a645e1a49a6e8c` — Aashutosh, Rework camera-guided body and garment scans.**

| Work | Ref/head at refresh | Actual status / disposition |
| --- | --- | --- |
| Main | `b3e0397eb6ac1ce8ab13b84e00a645e1a49a6e8c` | Integration baseline, not modified directly |
| [PR #25](https://github.com/anshbalusa-ui/itchathon/pull/25) | `feature/measurement-avatar-demo-m1`, `21e5728afbd0d2c1cfe367437ab796905537ddcb` | MERGED; head is ancestor of main; preserve |
| [PR #26](https://github.com/anshbalusa-ui/itchathon/pull/26) | `fix/tryon-draping-scan-performance-20261107`, `d204d77e3479f5500b75cf6803786da843ac8b45` | MERGED; head is ancestor of main; preserve |
| [PR #27](https://github.com/anshbalusa-ui/itchathon/pull/27) | `integration/onyou-final-gap-audit-20261109`, `f84435a307922aab8e27eab47b27cfd90b58c9d7` | MERGED; head is ancestor of main; preserve |
| [PR #28](https://github.com/anshbalusa-ui/itchathon/pull/28) | `review/onyou-release-readiness-20261110`, `16dccd39162dfcb3519d3cfc8f7211446b6d5b24` | OPEN draft, base is older integration branch; selectively adapt unique delta |
| [PR #29](https://github.com/anshbalusa-ui/itchathon/pull/29) | `feature/onyou-stationary-scan-refinement`, `45b5db23c53fc38198ee043d950881f40766f100` | OPEN draft, based on current main; two reviewed commits integrated |
| Smooth avatar | `feature/onyou-smooth-avatar-20261113`, `3d96b671bbef02bc4156d3fb9a031173d4ad0658` | Diverged at `f84435a`; inherits PR #28. Only compatible geometry-generation lifecycle adapted |

Created a new worktree `onyou-foundation-20261122` and branch **`integration/onyou-foundation-20261122`** from the verified remote main. The earlier refinement/readiness/smooth/testing worktrees and teammate branches were not rewritten. The existing `onyou-fitted-shorts-20261116` worktree had uncommitted README, body-generator, smooth-mesh, geometry-test and UI-test changes plus untracked fitted-shorts source/tests; those were left intact and are **not** silently included here. Initial worktree states were recorded outside Git. No reset, destructive cleanup, stash, force-push or main checkout/edit was used.

Main has five newer scanner/garment repair commits beyond the older readiness/smooth base. Whole older-branch file replacement would restore obsolete source or discard newer tests. Reviewed exact unique commits/deltas instead. No source changes were made to PR #28/#29 or their branches, and neither PR is merged/closed by this task.

## 2. Authoritative feature inventory

Classification refers to **starting main** and reviewed unmerged work. `IMPLEMENTED IN MAIN` is a source statement, not a physical pass. A separate evidence boundary remains even when implementation exists. `UNVERIFIED` is not permission to rewrite an otherwise coherent system.

| Feature | Classification | Source evidence and consolidation decision | Verification boundary |
| --- | --- | --- | --- |
| Body scanning | IMPLEMENTED IN MAIN | `BodyCaptureModel`, `BodyCaptureCamera`, `BodyScanFlowView`: capture → native processing → review/save exists. Preserve architecture. | Full rotating-human output/accuracy UNVERIFIED |
| Stationary camera | IMPLEMENTED IN MAIN | Camera runtime locks a calibrated camera reference and rejects movement while the subject turns. No walking-camera replacement. | Real mounting/room/movement behavior pending |
| Body-turn detection | IMPLEMENTED IN MAIN | `BodyCaptureFrameAnalyzer`, `BodyCaptureTurn`: Vision shoulder/hip/body axes and yaw continuity/reacquisition. | Profile/back/non-rigid human behavior pending |
| Angular coverage | IMPLEMENTED IN MAIN | `BodyCaptureCoverage`: 60 distinct photos, 32/36 bins, max 20° gap, three front-region full-body views; `BodyCaptureSpatialGuide` renders saved bins. | Angular logic is not anatomy evidence |
| Segmentation and LiDAR | IMPLEMENTED IN MAIN | Single `ARSession`, matched `ARFrame` RGB/depth, reusable Vision requests, confidence/foreground filtering, staged `BodyCaptureArchive` publication. | Native edge/intrinsics/depth interpretation pending |
| Full-body framing/calibration | IMPLEMENTED IN MAIN | `BodyCaptureEvidence` requires head plus both shoulders/hips/ankles, not merely an unclipped silhouette; `BodyCaptureCalibration` requires stable/fresh front evidence and arm/depth/pose gates. | Crown/toes/occlusion/lighting and all anatomical regions not proven |
| Countdown and ordinary voice | IMPLEMENTED BUT UNMERGED | PR #29 `BodyScanCameraStatus`, `BodyCaptureModel`, `BodyScanVoiceGuidance`/flow: self-arming, five-second countdown, fresh-framing wait, local speech/VoiceOver. Integrated here. | Actual scheduling/audio/solo usability physically UNVERIFIED |
| Missing-angle recovery | IMPLEMENTED IN MAIN; PR #29 polish unmerged | Turn/coverage/archive retain admitted views/direction; PR #29 directly arms recovery and carries coherent native IDs. | Native rejected-view recovery with real humans pending |
| Reconstruction | IMPLEMENTED IN MAIN; PR #29 repair unmerged | `PhotogrammetrySession` model/poses, rejected/skipped samples, texture/bounds checks. PR #29 repairs coherent-pose photo/sector floors; adopted unchanged. | Apple's rigid-object support does not establish articulated-human reconstruction |
| Saved-avatar validation | IMPLEMENTED IN MAIN | `AvatarScanInput`, `ScannedAvatarGeometry`, `PreparedAvatarScene`, `AvatarScanRecord`/store validate counts, scale/bounds, textures and exact content hash. | Sanity/integrity are not metrological accuracy |
| Avatar viewer | IMPLEMENTED IN MAIN | `YourBodyView`/`BodySceneView`: saved scan takes precedence over example/manual illustration; orbit/zoom and native camera/garment ownership preserved. | Source/UI evidence is not personal likeness |
| Smooth geometry | IMPLEMENTED IN MAIN; additional changes unmerged | CC0 anatomical reference, regional deformation and recomputed normals already exist. Smooth branch's cached async/latest-generation lifecycle adapted; its broader remeshing/section/shape changes deferred. | Optional manual illustration is not statistical reconstruction |
| Closet | IMPLEMENTED IN MAIN | `ClosetStore`/views: local records, image IDs, reference and replacement transactions. No rebuild. | Physical scan/measurement quality pending |
| Automatic shirt scanning | IMPLEMENTED IN MAIN | `GarmentCaptureCamera`, `GarmentDepthAnalyzer`, `GarmentLandmarkDetector`, plane projection and three agreeing frames; explicit review/save/retake. | GarmentIQ scores are not accuracy probabilities; physical endpoint study pending |
| Garment representation | PARTIALLY IMPLEMENTED | `GarmentPatternEvidence` binds 25 observed image landmarks to PNG hash; metric flat width/length/sleeve span and continuous illustrative shell exist. | No manufacturing 2D pattern/seams/material model |
| Shirt-on-avatar try-on | IMPLEMENTED IN MAIN | `TryOnBuilder`, surface/pose/shell/prepared garment, `TryOnModel`: actual saved geometry/photo, bounded caches and cancellation. Preserve; no fallback successful bare avatar. | Illustrative, not validated drape/tension/pressure/fit |
| Privacy and persistence | IMPLEMENTED IN MAIN; one required reason unmerged | Protected/backup-excluded scan and closet files, hashed/atomic replacement, private failure logs and raw-work cleanup exist. PR #29 supplies the same missing DiskSpace reason as #28, exactly once. | Manual measurement/history UserDefaults remain a distinct legacy policy; physical lock/backup/fault behavior not established here |
| Tests and evidence | IMPLEMENTED IN MAIN; unmerged updates | Meaningful unit/UI suites and native verifier exist; PR #29 updates admission/codec/layout/teardown coverage; PR #28's driver repairs adapted without dropping later main cases. | Historical receipts below do not validate a newly combined head |
| Brand studio | NOT IMPLEMENTED | Legacy catalog/`GarmentSizeChart` models and a `brand` string are not a designer project/pattern/revision workspace. | New work specified, no frontend/backend shipped |
| Statistical avatar completion | NOT IMPLEMENTED | `BodyShapeKernel` scales a template from supplied measurements; no learned partial-evidence estimator, region support or calibrated uncertainty. | Model/data/commercial rights and validation required |
| Garment physics | NOT IMPLEMENTED | SceneKit materials and settling animation are appearance, not constitutive fabric/seam/contact simulation. | No physical pressure/fit prediction |
| Sizing/grading | PARTIALLY IMPLEMENTED | Legacy `SizeChart.swift`/`FitEngine.swift` store explicitly based size measurements and preference/physical-review rules; closet compares qualitative dimensions. | Not a brand grading engine or validated personal size recommendation |
| Older two-pass moving-camera/height-entry instructions | SUPERSEDED | Current stationary source and PR #29 self-guided flow replace that procedure. Historical reports remain labelled; obsolete steps not restored. | Never use old receipts/instructions as current acceptance |

## 3. Integrated PR #29, without rebuilding the scanner

Reviewed all 19 changed files and every current `BodyCaptureAlignment`/start-state caller. No language servers were configured, so callsite inspection used source search. Applied the two reviewed commits with provenance:

| Original | Consolidation commit | Scope |
| --- | --- | --- |
| `2e586ee06466b476230c594e3d99cf1bcdea591a` | `23fa37c` | Self-guided scan intent/countdown/wait, local speech, self-facing instructions, turn-rate feedback, coherent native-pose admission, privacy reason and meaningful regression/docs updates |
| `45b5db23c53fc38198ee043d950881f40766f100` | `3983412` | Accessibility footer repair, compiler-friendly render assertion, independent codec/native-capability coverage and teardown/stale-action regression |

Both apply to unchanged starting main; this is not a merge of an older scanner. Preserve:

- `BodyCaptureModel`'s generation fences, one countdown, event-driven waiting and native start reconciliation. Arming is intent, not permission to admit camera samples.
- `BodyCaptureCoverage.alignedCoverage`: filter individual correspondences at the existing 25° tolerance, refit only the basis, leave native pose values unchanged and return exact admitted IDs. The same IDs govern final input validation and recovery retention; a low median cannot let outliers supply completion.
- All photo/bin/gap/full-body/depth/pose/segmentation thresholds and native incomplete/missing-output/rejected-sample handling. Successful yaw tracking is not reconstructed personal geometry.
- One ARKit preview/capture source, Vision/depth association, angular spatial guide, saved textured USDZ validation, explicit acceptance and transactional storage.
- Local bounded `AVSpeechSynthesizer`, no microphone/service, independent speech mute, VoiceOver and lifecycle stopping. Physical audio/interaction remains pending.
- Shared shirt/haptic instructions and all unrelated garment capture/try-on algorithms.

A README inconsistency inherited from #29 is corrected: at accessibility sizes Start/Cancel is first **inside** the shared scrolling panel, while ordinary-size controls remain pinned; the calibrated camera viewport stays fixed across instruction changes.

## 4. PR #28: unique delta versus inherited old base

Reviewed #28's own commit separately from its older branch snapshot. An old file lacking a later main test or using old scan IDs is not itself a PR #28 deletion/new feature; it must not be imported wholesale.

| PR #28 path | Disposition in consolidation |
| --- | --- |
| `Sources/Support/PrivacyInfo.xcprivacy` | Duplicate exact DiskSpace `E174.1` change; already imported once through #29 |
| `Scripts/verify_development.py` | Duplicate exact required-reason expectation; no second edit |
| `Tests/IntegrationPrivacyManifestTests.swift` | Duplicate exact assertion; preserve once |
| `UITests/TryOnUITests.swift` | Adapted reopen-editor synchronization, safe lazy-Form targeting, slow interior Body swipe and collection-list gutter scrolling; retain current cases/assertions/scan IDs |
| `Docs/AutomaticGarmentCapture.md` | Adapted body subsection/current evidence boundary; flat-shirt overhead capture remains a separate unchanged workflow |
| `Docs/BODY_SCAN_AUDIT.md` | Retain original historical body and newer #29 historical annotation, not older conclusions presented as current |
| `Docs/ONYOU_DEVICE_VALIDATION.md` | Adapted prospective stationary-phone/person-turn cases; physical status NOT RUN, no mandatory measurements/two turns/second placement |
| `Docs/ONYOU_FINAL_RELEASE_READINESS.md` | Historical commit/fingerprint/receipt scope preserved, current verification separated, no release-ready claim |
| `Docs/ONYOU_FIT_VALIDATION_ROADMAP.md` | Adapted independent endpoint/metrology/uncertainty requirements, not old scanner thresholds |
| `Docs/ONYOU_RELEASE_CHECKLIST.md` | Adapted candidate-specific software/privacy/resource and future physical/distribution gates |
| `Docs/ONYOU_POST_MVP_ROADMAP.md` | SUPERSEDED by the single new execution roadmap; not copied |
| `README.md` | Do not copy old whole-file instructions/verification claims; current integration links and evidence boundaries maintained |

The original readiness evidence remains history, not rewritten into a new pass. Later main's shirt-dimension case, current `scan.unsupported`/`scan.camera.action` routes and rendered-pixel assertions remain. No extra exact accessibility-wording predicate or duplicate long measurement journey was imported from smooth; the current helper already waits for actual visible body pixels and a meaningful rendered change.

## 5. Smooth branch: adopted subset and explicit deferral

Candidate `3d96b671bbef02bc4156d3fb9a031173d4ad0658` inherits #28. Only its geometry-generation/lifecycle delta is adapted, not inherited privacy/docs or older whole scene files.

### Eight acceptance questions

| Question | Source-supported answer |
| --- | --- |
| Already in main? | Anatomical reference, deformation, normals, saved scan/viewer/garment behavior already exist. Cached async generation and latest-request publication protection did not. |
| Concrete improvement? | Actor owns prepared reference/kernel; cancellation checkpoints bound superseded work and late results cannot publish over newer requests. Removes reference load/shaping from the UI actor without claiming measured speed. |
| Scanned-avatar compatible? | Installing a saved scan cancels/invalidate pending manual generation and preserves the normalized scan owner. Separate native source/storage remains unchanged. |
| Coordinate/scale impact? | Adopted kernel retains current stations, height scaling, center and arm mapping. No subdivision, reference renormalization or recalibration is imported. |
| Shirt integration preserved? | Current scan/try-on result and garment node/cache ownership remain; optional manual illustration still cannot authorize personal scanned-avatar try-on. |
| Mandatory measurements? | No. Only the already-optional manual/example illustration uses `BodyMeasurements`; consumer scan onboarding remains measurement-free. |
| Stationary-scanner conflict? | No scanner/store/admission source changes arise from this subset. Saved scan precedence and callback generation fences are retained. |
| Safe claim without physical proof? | Cancellable correct-owner publication of the same illustrative geometry, not body accuracy, completion or fit. New source behavior still requires the scoped integration check below. |

### Actual code subset

- Add adapted `Sources/OnYou/BodyModelGenerator.swift`: cached actor using the **existing** admitted reference/body/shorts and kernel, with cooperative cancellation. No remesh or rescale.
- Adapt `BodySceneView.swift`: only latest request publishes; stale geometry is hidden during replacement; detach and saved scan supersede work. Preserve camera requests/gestures, reduced motion, settlement and garment ownership.
- Adapt `BodyShapeKernel.swift`: Sendable value and cancellation checkpoints while preserving the deformation/section algorithm and existing tests.
- Add `Tests/BodySceneLifecycleTests.swift`: actual generated geometry/latest request, detach, invalid-input recovery and saved-scan precedence. No mock echo or physical body assertion.
- Parent integration repair: wireframe mode used to be applied after synchronous generation. The async port would publish a default solid material after that update. Retain requested wireframe state and apply it when publishing; assert the actual material mode in the lifecycle case.
- Focused compilation exposed an omitted original `scannedNode` declaration in the selective port. Restored the same `SCNNode?` owner used by scan normalization, try-on yaw and teardown. The build-blocked attempt executed zero tests; this is not a defect attributed to Aashu's main.

### Deferred, not silently treated as merged

| Candidate work | Reason and future proof |
| --- | --- |
| Loop subdivision / reference Y renormalization | Changes reference topology/bounds and refinement budget; needs dedicated numerical/topology/visual comparison, not an unreviewed replacement of current smooth geometry |
| New central-section, shoulder calibration and arm mapping | Changes how optional manual dimensions deform torso/limbs. Preserve current section semantics/ranges until that coupled numerical change is validated |
| `SmoothMeshGeometry.swift` plus `MeasurementAvatarGeometry.swift` extraction | Shared-section cutover must migrate both consumers coherently; importing the utility alone duplicates logic. Existing DEBUG illustration remains unchanged |
| Pelvis component pruning / shorts remesh | A visual/topology cleanup candidate, not needed for native scanner integration; assess boundary/components against exact reference asset in a separate focused geometry task |
| Studio lighting / buffer-backed scene geometry | Independent appearance/data-layout/lifetime change, not needed for the thread/publication repair. Preserve current renderer; verify ABI/alignment/render parity before a separate cutover |
| Additional geometry tests / extra long UI journey | Deferred with corresponding geometry changes, not reported passed on this branch. Existing meaningful tests are preserved; no weaker assertions substituted |

These deferrals are technical scope/compatibility decisions, **not** an ownership restriction: `MeasurementAvatarGeometry.swift` was available for review. Lack of physical accuracy alone is not the reason to defer numerical geometry work; a later small code/visual comparison can run without a person. No additional main behavior is removed for unverified visual changes.

## 6. Consumer journey compatibility review

| Boundary | Preserved contract / decision |
| --- | --- |
| Capture identity and frames | `BodyCapturePhotoWriter` publishes RGB last only after paired depth/mask staging succeeds; same `ARFrame` supplies image/depth/camera. Sample IDs remain distinct through retained recovery |
| RGB/depth/mask orientation | RGB physically clockwise/upright JPEG orientation 1, depth rotated consistently, upright mask dimension/type checks. No imported older writer. Native calibration/intrinsics interpretation remains uncertain, not invented |
| Native viewpoints | Reconstructed poses feed coherent-ID filter; stationary AR camera pose is not substituted for a reconstructed orbit |
| USDZ coordinates/scale | `ScannedAvatarGeometry` uses consistency/Y-up/meters conversion and existing grounding/centering/legacy reference-height behavior. Front/physical scale is not independently proven |
| Avatar storage/replacement | `AvatarScanStore` validates exact bytes/model, stages protected new UUID content and atomically changes active record before removing prior model. Failed/canceled work does not replace the saved avatar |
| Image and dimension association | `ClosetGarment.imageID`, capture dimensions and `GarmentPatternEvidence.imageSHA256` remain exact-photo bound. Photo-only imports gain no fake metric dimensions |
| Garment representation | Flat shirt width/length/sleeve span and admitted landmarks are not manufacturing pattern/seam/material evidence. No draping algorithm changed |
| Pose/attachment | `TryOnSurface`/pose estimator and garment shell use the saved native scene; unsupported pose rejects rather than substituting generic successful body/garment |
| Cache ownership | `TryOnBuilder` retains bounded one-avatar/pattern/scene caches and verifies source hashes even on reuse. `BodySceneView` owns per-view camera/garment nodes, not shared mutable scenes |
| Cancellation and recovery | Existing task generations, native unwind-aware cleanup, retry versus missing-view versus retake paths preserved. Added manual scene publication fences cannot override a saved scan |
| Provenance | Examples/manual geometry and authored UI fixtures remain labelled, separate from personal scans. No inferred mesh or brand garment forged into current camera evidence |
| Errors/privacy | Existing private capture error logging, generic recovery, protected scan/closet files and backup exclusions preserved. No upload, personal data logging, account or new external service |

No direct storage-format, garment-scale or current saved-avatar migration incompatibility justified rebuilding the consumer journey. The two focused render-integration repairs above are the actual new defects resolved; native human reconstruction uncertainty is documented rather than bypassed.

Final driver review also restored the original `reveal` helper's early success return when its target is already hittable. The selective PR #28 port had accidentally omitted that guard, which would perform all eight swipe attempts even for a visible target. No assertion, current test case or production capture behavior was weakened. This is an integration-driver repair, not a claimed application speed improvement.

## 7. Architecture and next implementation

[Platform architecture](ONYOU_PLATFORM_ARCHITECTURE.md) specifies the retained Swift consumer app, proposed local-first desktop-browser studio, minimum shared unit/provenance/version contracts, licensed statistical fitting prototype, simulation feasibility and compatibility/consent rules. These are implementation-ready future boundaries, not unconsumed production models or installed frameworks.

[Execution roadmap](ONYOU_EXECUTION_ROADMAP.md) provides Goals 1–7, exact missing work, reused code, affected modules, deliverables, definitions of done, ownership and no-rebuild limits. Recommend **Goal 1: narrowly harden the actual countdown/native-start/pause/generation/recovery coordinator**. The existing status-policy test is not a deterministic task-ordering test. Its ready-to-use task permits only affected checks, no physical capture or broad campaign. Studio Goals 2–3 can progress on standardized models in parallel with licensed completion Goal 4; neither needs completed personal inference.

## 8. Evidence and remaining gates

### Historical, not combined-branch proof

| Receipt | Exact source | Meaning / limit |
| --- | --- | --- |
| PR #28 | `16dccd39162dfcb3519d3cfc8f7211446b6d5b24`, source fingerprint `5d3963a6f10f9992caf70b3fa27e35c712e7883eb79f6c20d2d7b63834172770` | Documented 439 Debug / 21 Release cases plus builds/bundle/resource checks on that older candidate. Not current scanner, current source or physical evidence |
| PR #29 | `45b5db23c53fc38198ee043d950881f40766f100`, source fingerprint `c5cfac04f51dc0e90d31605a215d7968c27112eff5caed6ba5cfbc454fad09fd` | Selected 80 passed, zero failed, two hardware-dependent skips; actual app/chrome fixtures inspected. No live personal scan, human reconstruction, physical fit or current consolidation proof |
| Smooth candidate | `3d96b671bbef02bc4156d3fb9a031173d4ad0658` | Source/tests reviewed; any branch-specific historical result is not transferred to the adapted subset |

Local source review covered the actual paths above, branch diffs and old receipt identity. No physical phone, LiDAR/person scan, garment sample, credentials, dataset/model download or performance benchmark was required or performed for consolidation. No broad regression/Release/distribution campaign was launched.

### Newly verified bounded integration smoke

The final reviewed source fingerprint from the existing `Scripts/verify_development.py` digest is **`4f0897f235c04c6e0a43b6b0b1f7b66a3ee3a1c71d2f13de0fbdb7fc06ec0241`**, unchanged before/after the run. Environment: unsigned Debug `FitCheck`, iPhone 17 simulator, iOS 26.5, x86_64. **Five passed; zero failed, skipped or expected failures.** This is not a full suite or native reconstruction result.

| Executed case | Actual result / scope |
| --- | --- |
| `BodySceneLifecycleTests/testRapidMeasurementChangesPublishOnlyLatestAndDetachCancelsPendingWork` | Passed; latest geometry, pending wireframe material and detach cancellation |
| `BodySceneLifecycleTests/testInvalidUpdateHidesStaleGeometryAndCanRecover` | Passed; stale geometry hidden on invalid input, valid recovery |
| `BodySceneLifecycleTests/testSavedScanSupersedesPendingMeasurementGeometry` | Passed; actual saved asset takes precedence over pending manual generation |
| `TryOnUITests/testManualMeasurementsChangeRenderedBodyWithoutAuthorizingScanTryOn` | Passed; actual rendered shape changes, editor/history path and scan-required boundary with visibly synthetic data |
| `TryOnUITests/testSavedAvatarClosetTryOnRotationVisibilityAndReopening` | Passed; actual fixture avatar/closet/shirt rendering, rotation, visibility and reopening |

Exact bounded selection, run from the integration worktree:

```sh
xcodebuild -project 'On You.xcodeproj' -scheme FitCheck -configuration Debug \
  -destination 'platform=iOS Simulator,id=D5BE86CA-76FC-4C6A-BD88-5D29FFF910F5' \
  -derivedDataPath /Users/anshbalusa/onyou-foundation-evidence-20261122/Derived \
  -resultBundlePath /Users/anshbalusa/onyou-foundation-evidence-20261122/FocusedFinal.xcresult \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO \
  -only-testing:FitCheckTests/BodySceneLifecycleTests \
  -only-testing:FitCheckUITests/TryOnUITests/testManualMeasurementsChangeRenderedBodyWithoutAuthorizingScanTryOn \
  -only-testing:FitCheckUITests/TryOnUITests/testSavedAvatarClosetTryOnRotationVisibilityAndReopening \
  test -quiet
```

Local evidence is outside Git at `/Users/anshbalusa/onyou-foundation-evidence-20261122`: `FocusedFinal.xcresult`, input/summary/tests/source JSON, exported attachments/manifest and `Normal-app.png`. Inspected actual fixture shirt rendering, changed manual body, explicit scan-required screen and normal app surface. The normal launch used `Scripts/launch_onyou.sh --simulator D5BE86CA-76FC-4C6A-BD88-5D29FFF910F5 --app '…/Derived/Build/Products/Debug-iphonesimulator/On You.app'` without fixture flags; the rendered default is explicitly **Example body**, not a personal scan. Fixture screenshots explicitly say synthetic/not a scan.

The first bounded attempt was compile-blocked by the omitted `scannedNode` property: **zero tests executed**, retained as `FocusedIntegration.xcresult`. After restoring the existing field, an intermediate five-case run passed on fingerprint `4894f65a67db7fda7b37ab3a179d6739d434784d29452f7caa799e90369e6007`. Final diff review then restored the driver's original early return and removed two introduced whitespace-only lines. The final five-case result above binds to the resulting source; intermediate passes are not counted again.

The built Debug privacy manifest was inspected: DiskSpace `E174.1` appears once, tracking is false and collected-data declarations remain empty. This is not App Store privacy approval or Release bundle proof. `git diff --check origin/main` passed after removing the introduced whitespace. All ten pre-existing worktrees retain their original tracked/untracked path statuses, including the seven fitted-shorts work paths; the branch-header difference between status-command formats was normalized, not mistaken for a file change. PR #28/#29 remain open drafts at their original reviewed heads; fresh GitHub main remained `b3e0397…`.

### Remaining platform and physical gates

Remaining physical/platform uncertainty: real countdown/audio/VoiceOver use, lighting/space/occlusion/framing, phone movement and native rotation tracking; articulated-human native reconstruction, image/mask/depth/intrinsics behavior, full anatomy, front orientation, real metric scale/likeness and garment accuracy. Statistical completion, manufacturing grading, material mechanics and publishing remain future work with separate rights/proof gates. Current illustrative rendering and geometric sanity do not establish them.

### Observed existing UI limitation, not an accessibility sign-off

The largest-accessibility-text attachments show the retained Body screen's long measurement-illustration caption clipped beneath the preview and oversized controls overlapping the bottom tab region in the captured viewport. The driver can scroll/reach the relevant controls and the behavior assertions pass; that does **not** establish a polished large-text layout. Normal-size launch was visually inspected separately. The Body screen layout was not redesigned during source consolidation; record this as deferred UI/accessibility work, not a passed release gate.

## 9. GitHub delivery

- Dedicated branch: `integration/onyou-foundation-20261122`, created from verified `origin/main` `b3e0397eb6ac1ce8ab13b84e00a645e1a49a6e8c` in an isolated worktree.
- [Draft PR #30](https://github.com/anshbalusa-ui/itchathon/pull/30) targets `main`. No automatic merge or modification/closure of PR #28/#29 is authorized or performed.
- Code/documentation integration commit: [`f7ed7ee0b71f4dfa836c1228ca6c42415c91c40d`](https://github.com/anshbalusa-ui/itchathon/commit/f7ed7ee0b71f4dfa836c1228ca6c42415c91c40d), following the two provenance-preserving PR #29 cherry-picks `23fa37c` and `3983412`.
- This delivery section is a documentation-only receipt added after the actual PR URL existed. The [PR commits/current head](https://github.com/anshbalusa-ui/itchathon/pull/30/commits) identifies the final publication revision; it does not change the compiled source fingerprint or reclassify historical tests.
- Main, the reviewed teammate heads and all ten pre-existing worktrees were left intact. Existing uncommitted fitted-shorts work remains separate, not silently imported or overwritten.
