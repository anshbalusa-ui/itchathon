# On You — final gap audit and targeted integration

## Scope and source of truth

Audit completed before application architecture or feature changes. This is integration/finalization, not a rebuild. Customer-facing name **On You**; Swift module/scheme **FitCheck** remains intentional.

- Live GitHub refresh: latest `main` is `9b97ab387649a5da26ab01285c7957ae454b19c5`; PR #24 is merged.
- PR #25 is an open draft at `21e5728afbd0d2c1cfe367437ab796905537ddcb` (measurement-avatar demo).
- PR #26 is an open draft at `d204d77e3479f5500b75cf6803786da843ac8b45` (actual On You try-on/capture repair).
- Finalization branch: `integration/onyou-final-gap-audit-20261109`, created directly from current `origin/main` in a new worktree. Existing PR worktrees were clean and remain untouched.
- Main's newer native application commits were reviewed, including textured body capture, offline GarmentIQ/Closet integration, capture transitions and the current try-on connection. Other remote feature heads correspond to already merged milestones; no additional unmerged teammate implementation was found beyond the two open drafts.
- PR #25 and #26 overlap only in `README.md` and `Scripts/verify_development.py`. Current `Project.json`, customer-facing identity, SceneKit flow and persistence contracts take precedence over obsolete project metadata.

Statuses: **DONE**, **READY TO INTEGRATE**, **NEEDS FIX**, **MISSING**, **NEEDS DEVICE VALIDATION**, **OPTIONAL**. Historical verification is explicitly not a fresh integrated-branch result.

## Feature-by-feature decision

| Feature | Status at audit | Existing implementation / evidence | Actual remaining problem | Necessary code action |
|---|---|---|---|---|
| 3D avatar viewer | **DONE** | Main `BodySceneView`, `BodyShapeKernel`, pinned CC0 human asset; `OnYouTests.testMeasurementShapesMatchTorsoSectionsAndHeight` checks real vertices, sections, height and normals. PR #26 has actual Body/try-on screenshots and native rendered tests. | Combined branch still needs a fresh smoke; no new renderer is missing. | Keep current SceneKit viewer and existing Metal labs; no replacement. |
| Measurement-driven avatar | **READY TO INTEGRATE**; native editor reachability **NEEDS FIX** | PR #25 has `MeasurementAvatarGeometry`, model/view, renderer support, 14 added Debug cases and a Release exclusion case. Main independently already has tested `BodyShapeKernel`, `BodyMeasurementsView`, parser/store/history. | In latest main, `BodyMeasurementsView` has zero callsites: Body exposes scan/delete and History exposes snapshot/restore only. README still advertises editing. The M1 generator is intentionally a separate Debug-only, non-persistent illustration. | Integrate original M1 code/tests/routes unchanged where compatible. Add a minimal navigation route to the existing native editor; do not create another generator, replace the working kernel, or turn manual values into a captured scan. |
| Native LiDAR body scanning | **NEEDS DEVICE VALIDATION** | Main `BodyCaptureModel` uses native Object Capture/Photogrammetry; PR #26 improves existing feedback, cancellation and off-UI preparation. `AvatarScanTests`/`AvatarScanInputTests` enforce two passes, >=60 accepted images and positive finite retained depth. | Physical framing, depth quality, repeatability and device accuracy are **NOT RUN**. | Preserve software/admission; integrate reviewed PR #26 changes only. |
| Body reconstruction and storage | **DONE** software; physical reconstruction **NEEDS DEVICE VALIDATION** | Main scale/texture/model checks and atomic `AvatarScanStore`; tests cover textured artifact persistence, corruption, failed replacement and deletion isolation. PR #26 reuses prepared finished geometry. | No new reconstruction engine is missing. Native sample initialization/reconstruction cannot be validated by Simulator. | Preserve existing reconstruction and file formats; reuse PR #26 preparation. |
| Clothing closet | **DONE** core; PR #26 refinements **READY TO INTEGRATE** | Existing `ClosetStore`, detail/capture UI and image persistence; PR #26 binds retained observations to exact image SHA and keeps retakes atomic. Existing Closet/lifecycle tests. | Fresh combined selection/persistence checks needed, not another catalog. | Keep current closet and storage; integrate original refinements. |
| Automatic shirt scanning | **READY TO INTEGRATE** | PR #26 native model service, exact image canvas/portrait UV mapping and bounded frame scheduling; `ClosetTests` exercise native licensed-photo inference, distinct-frame consensus, timing, mapping and invalid depth. | Real clothing/background/depth capture repeatability **NOT RUN**. Authored fixture observations are not native recognition. | Reuse PR #26; no alternate detector or camera-success mock. |
| Shirt-on-avatar try-on | **READY TO INTEGRATE** | PR #26 actual Body → Closet → shirt → same-scene native garment. `TryOnTests` and `TryOnUITests` check actual garment pixels, orientation, selection, visibility, reset, dismissal/reopen and failure recovery. | Main's old Vision-pose path fails on the authored fixtures; this is already repaired in PR #26. | Integrate original repair, not another try-on implementation. |
| Garment geometry/draping | **READY TO INTEGRATE** | PR #26 connected implicit shell, observed-surface envelope, UV/index/normal and clearance checks. `RenderedGeometryInspection.json` records 20 native views across A/B × Tide/Coral × five angles. | No demonstrated remaining geometry defect after the reviewed hip-shelf repair. Illustration/inferred rear is not physical fit. | Reuse mesh/envelope unchanged; repair only an integration regression if reproduced. |
| Scan speed / performance | **DONE** for measured workloads; **NEEDS DEVICE VALIDATION** for native reconstruction | Existing `performance-comparison.json`: identical warm section construction 921.1 → 426.4 ms (53.7% observed reduction). Cold garment mesh remains several seconds; same-builder reuse is not reopen latency. Native photogrammetry was unsupported in both runs. | No changed integration workload or new regression is demonstrated. Phone scanning/reconstruction timings **NOT RUN**. | Preserve benchmarks/optimizations; do not repeat them or claim hardware speedups. |
| Scan guidance and UX | **READY TO INTEGRATE** | PR #26 Frame/Body/Detail/Build feedback, corrected pass numbering, capacity/interruption recovery; `BodyScanUXTests`, capture scheduling tests and disclosed component captures. | No new guidance system is needed. Physical camera guidance quality remains unvalidated. | Preserve reviewed improvements and their conservative SDK evidence boundaries. |
| UI / navigation | **NEEDS FIX** only for dormant native measurement editor; other PR routes **READY TO INTEGRATE** | Main's actual tabs/scan/Closet routes; PR #26 native journeys and compact/largest-AX proof; PR #25's existing internal hub/showcase links. | Native measurement editor is unreachable. Legacy `launch_friday_demo.sh` still hardcodes old `FitCheck.xcodeproj` / product / bundle while main is `Project.json` / On You. | Wire existing editor minimally; reconcile existing launch metadata and retain both Debug routes. No redesign. |
| Persistence / privacy | **DONE**; reviewed PR #26 association/lifecycle changes **READY TO INTEGRATE** | SHA admission, complete file protection, backup exclusion, atomic replacement, isolated stores, corrupt-data retention and history/deletion tests. Separate manual-measurement and captured-scan namespaces. | No format migration or authorization relaxation is justified. | Preserve formats, ownership and recovery; verify integration only. |
| Automated tests / build integration | **READY TO INTEGRATE**; obsolete main verifier **NEEDS FIX** via existing PR #26 | PR #25 historical 381 Debug / 18 Release, zero skips; PR #26 final 424 Debug (387 unit + 37 UI) / 20 Release (9 + 11), zero skips; 362 current-main original unit identities represented. Main verifier still references removed `project.yml` and old app paths. | Combined verifier must retain PR #26 actual project logic plus M1 markers and Release selector. Integrated totals are not yet known. | Reconcile existing verifier rather than rewrite it. Retain every existing case; add only a consumer regression for the demonstrated navigation gap. |
| Real-device / physical-fit validation | **NEEDS DEVICE VALIDATION** | Native software exists; current `xcrun xctrace list devices` shows only the Mac and simulators available, with a phone listed offline. No valid real-person capture/fit dataset is present. | Physical capture, calibration accuracy, likeness, reconstruction speed and actual garment fit/pressure **NOT RUN**. | No code rewrite, private scan request, invented accuracy number or fit claim. |

## Reuse and integration contract

1. Incorporate PR #26's reviewed current-main repair first, retaining actual `Project.json`, On You identity, protected storage and native application flow.
2. Incorporate PR #25's existing Debug measurement geometry/model/view, renderer-specific support, routes and all tests. Keep the main native measurement kernel/view instead of replacing it with another architecture. Generated demo values remain distinct from captured avatars and are not persisted as scans.
3. Reconcile only shared README/verifier content, preserving both suites and M1's `testMeasurementDemoIsExcludedFromRelease` selector/markers alongside PR #26's Release/resource checks.
4. Correct the existing internal launch helper's obsolete project/product/bundle metadata without adding a second launcher architecture.
5. Wire the existing native measurement editor and prove editable numbers change the real model and save through the existing separate store/history. A saved captured avatar must not be overwritten or relabeled by manual data. No requirement is inferred to authorize manual geometry for captured-avatar try-on.

No other new implementation is justified by this audit. Authentication, cloud services, new retailers, payments, face intake, physical cloth/pressure/fit algorithms and a replacement renderer are **OPTIONAL** and will not be implemented.

## Verification and visual reuse

- Prior receipts are immutable historical evidence: PR #25 `/Users/anshbalusa/fitcheck-m1-artifacts/full-verification/verification-1n5bxsj5/verification.json`; PR #26 `/Users/anshbalusa/onyou-tryon-artifacts-20261107/FinalVerification4/verification-f6w46tyn/verification.json`.
- Existing M1 screenshots/recording and PR #26's four-pair native rendering/benchmark/media proofs will be reused for unchanged features. They do not establish a pass on this new combined tree.
- Fresh integrated verification must execute the union of current-main/PR #25/PR #26 cases, normal Debug/Release and unsigned iPhone SDK builds, Release exclusions and resource/privacy inspections. No deleted/skipped/weakened cases or substituted mock success.
- Capture only actual screenshots needed to establish new integration: ordinary On You saved-avatar shirt rendering, the newly reachable existing native editor, and coexistence of original M1 routes where necessary. No decorative image generation or redundant recordings are planned.

## Targeted completion after audit

- The pre-change audit was committed first (`eac1beb`); both reviewed PR heads were then merged into the dedicated branch with their original histories retained. README reconciliation keeps native On You and the separate M1 lab. The verifier retains current project/resource/privacy logic plus every M1 marker and its Release exclusion selector.
- The only new application integration is the existing native measurement editor's optional Body entry, using the same modal `NavigationStack` pattern as Closet. It retains the existing kernel, parser, store and history. Captured avatars still take priority; manual models neither replace scans nor authorize captured-avatar try-on.
- Actual largest-accessibility recordings exposed truncated Body captions/actions and broken-word measurement labels. The existing bounded-preview/scrollable-controls pattern from try-on is reused only at accessibility sizes, and measurement rows stack labels above their existing inputs there; normal presentation and both rendering engines are retained.
- The internal launcher reproduced rejection of a renamed iPhone and a missing `project.yml` failure. Its selection now uses iPhone device type and its build/product/bundle metadata comes from the actual `Project.json`. Original failures: `/Users/anshbalusa/onyou-finalization-artifacts-20261109/LegacyLauncherReproductions.json`.
- M1's Release exclusion case still checked the obsolete “My Body” title. That copy assertion is removed in favor of the real native Body viewer launch contract; all four M1 exclusion checks and the case identity remain. The older legacy-home contract was already migrated upstream to `AvatarPilotUITests.testExplicitLegacyLaunchAndInternalOptInRemainIsolated`; it is not deleted or recreated here.
- The new consumer UI regression exercises actual rendered body changes, lazy native numeric fields, cancellation/reopening, saved History, largest text/touch targets, retained Closet data and refusal to treat manual geometry as a saved scan. Intermediate failed attempts remain in the external evidence directory; only completed final receipts count as passes below.

## Completion evidence

At delivery, every **READY TO INTEGRATE** entry above is integrated and every **NEEDS FIX** entry is repaired. Working engines, storage formats, capture/admission requirements and benchmarked algorithms were not rebuilt. Physical-validation entries remain **NEEDS DEVICE VALIDATION / NOT RUN**.

| Fresh verification | Observed result |
|---|---|
| Complete Debug suite | **439 passed**: 399 unit + 40 UI; 0 failed, 0 skipped, 0 expected failures |
| Release isolation | **21 passed**: 9 unit + 12 UI; 0 failed, 0 skipped, 0 expected failures |
| Unsigned generic iPhone SDK Debug build | PASS |
| Normal Release build | PASS; `ENABLE_TESTABILITY=NO` |
| Resource/privacy inspections | PASS in Debug, iPhone SDK, normal Release and Release-test app bundles; no Release development resources/markers; pinned production human asset retained |
| Existing regression identities | All 362 original current-main unit cases, all 424 PR #26 Debug cases and all 14 added M1 Debug cases represented; no missing required identities |
| Additional consumer coverage | Native numeric editor at largest accessibility text: Cancel/reopen, real rendered shape change after Save, History, retained Closet and refusal to authorize scan try-on from manual data |
| Physical camera/LiDAR/fit validation | **NOT RUN** |

Verified source fingerprint: `18f25b290081ff9533c5f397068f00c302a469bb381a0dfb22ac68c132d7c340`. The full gate freezes all source/test/project/verifier inputs; subsequent completion edits are documentation only.

Local evidence root: `/Users/anshbalusa/onyou-finalization-artifacts-20261109/`.

- Full receipt/build logs/xcresults: `FullVerification/verification-kqxe8wp7/verification.json`.
- Exact regression preservation: `IntegratedRegressionPreservation.json`.
- Actual unedited simulator screenshots: `FinalVisualEvidence/manifest.json`; native app index with absolute paths and provenance: `FinalVisualEvidence/onyou-integration-index.json`.
- Visually inspected native shirt front / side / back / second garment: `FinalVisualEvidence/A8051560-2833-42FA-863D-1661D494F152.png`, `5EE583E4-9D3A-4099-A820-7D631B51B63D.png`, `6C8A6194-E9D8-4ABA-9563-1C68E7AE7A44.png`, `6DE92B50-1707-4326-988F-0A835020EA95.png` in that directory. The index also identifies manual editor, saved model, History, missing-scan recovery and distinct-body/accessibility captures.
- Before/after and launch receipts: `TargetedRuntimeProof.json`, `LegacyLauncherReproductions.json`, `MeasurementRouteBefore.xcresult` and passing `MeasurementRouteAfter6.xcresult`. Earlier failed implementation/automation attempts remain intact, not counted as passing runs.

Both launch paths were freshly exercised: the repaired `Scripts/launch_friday_demo.sh` generated the current project, built/installed the current Debug app on a renamed iPhone and opened the genuine Metal showcase; `Scripts/launch_onyou.sh --fixtures` with the full gate's verified Debug `--app` opened the actual On You app. The latter remains open in Simulator. Standard build-from-source commands and the separate Debug lab are documented in README.

Remaining work is physical validation, not a second implementation: real capture/retakes/lighting, reconstructed body likeness and metric accuracy, device performance and garment-dimension/fit validation. Manual geometry remains a generic measurement illustration; the shirt shell is geometric, with inferred rear material and no physical cloth/pressure model. Cold mesh preparation can take several seconds on this Intel simulator; existing off-main/cancellation/cache improvements are retained, with no new phone-speed claim.
