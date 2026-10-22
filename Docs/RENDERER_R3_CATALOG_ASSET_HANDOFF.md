# Segment R3 — catalog to verified file-backed garment preview

## Baseline and integration

- Repository/workspace: `anshbalusa-ui/itchathon`, `/Users/anshbalusa/fitcheck-recovery-20261020`.
- Starting branch/PR: `feature/bundled-3d-asset-pipeline-r2`, draft PR #15.
- Exact verified base: `c947f18e1e380325ac8879ad30c625a43e1f8bfd`; local and fetched remote matched. The worktree was clean; PR #15 remained open/draft and no newer PR superseded it.
- New branch: `feature/catalog-bundled-garment-r3`. Draft-PR target is the R2 branch, not main. No merge, rebase, cherry-pick or unrelated cleanup was performed.
- Draft delivery: [PR #16 — exact catalog SKU to verified file-backed garment preview](https://github.com/anshbalusa-ui/itchathon/pull/16), targeting `feature/bundled-3d-asset-pipeline-r2`. It is not merged.
- The prior R2 totals (225 Debug / 12 Release tests) are historical baseline evidence, not fresh R3 results.

R3 authorizes one exact first-party fixture as a **fictional internal catalog illustration**. It does not turn the fixture into an authentic retailer garment, license an external asset, represent a customer's body, resize geometry from S/M, or estimate fit.

## Exact product and approved associations

The existing `SyntheticCatalog` receives one additional product. Existing T-shirt identities, variants, colors, availability states and prices remain unchanged.

| New fixture field | Definition |
| --- | --- |
| Retailer / product | `sample-studio` / `geometric-vest` |
| Display title / category | Geometric Vest Concept / `vest` |
| Color | `navy`, Navy, `#24364B` |
| Sizes | `small` → S; `medium` → M; labels only |
| SKUs | `geometric-vest-navy-small`, `geometric-vest-navy-medium` |
| Availability | `available` in the synthetic source only, not real inventory |
| Provenance | `synthetic`, revision `sample-v1`, reference `local-synthetic-fixture` |
| Commercial/media/measurement fields | No price, photograph, finished measurements or purchasable offer |

The description identifies a fictional browsing concept, not a physical garment or an item for sale. `CatalogCategory` adds `vest`; the separate legacy measurement/fit category domain is not extended or reused.

The **existing** six-row `CatalogPreviewAssociation` registry is the only product-to-illustration authorization boundary:

| Exact sample SKUs | Material | Geometry source |
| --- | --- | --- |
| `everyday-navy-small`, `everyday-navy-medium` | Navy | Original procedural shirt |
| `weekend-sage-small`, `weekend-sage-medium` | Sage | Original procedural shirt |
| `geometric-vest-navy-small`, `geometric-vest-navy-medium` | Navy | Exact reviewed R2 bundled vest |

Every row uses retailer `sample-studio` and its exact corresponding product ID. Tee rows require `tshirt`; vest rows require `vest`. Resolution validates the loaded product's domain constraints, scoped identity/category, exact synthetic provenance/revision/reference, selected color ID/name/hex, selected size membership, current listed SKU/options/availability, checked selected-response SKU/options/availability and the appropriate strict fixture declaration. Both snapshots must report available. A title, category, size label, hex value or a matching foreign option tuple cannot authorize another product/SKU.

Missing selections, foreign IDs, changed category/provenance, wrong listed membership, stale/foreign variant responses, discontinued/out-of-stock/unknown states and unavailable/incompatible fixtures fail closed. Cream remains unsupported; Archive remains discontinued and unassociated. No fallback SKU or material is substituted. Prices remain catalog data, not geometry inputs.

The original procedural and new bundled dependencies are independent. A missing bundled declaration does not disable approved procedural previews; a missing procedural declaration does not disable the explicitly approved vest. Invalid bundled descriptors are not passed into the procedural validator. Old procedural descriptors remain exact and valid under their unchanged R0 policy.

## Geometry-source and loader contract

`RendererGeometrySource` is a small immutable Hashable enum: `.procedural` or `.bundled(RendererBundledAssetDescriptor)`. `RendererPresentation` gains this source, defaulting to procedural. Catalog preview snapshots include it in their identity and pass only presentation/scalar/descriptor data to the renderer. Low-level rendering imports no catalog repository or product domain.

Descriptors gain Hashable conformance for immutable navigation identity; their validation rules, fixed resource mapping and expected digest are unchanged. A presentation is not a general remote request, raw file URL or retailer entitlement. The association produces only the two reviewed geometry choices; malformed declarations still fail the loader's own strict policy.

The vest remains:

- Asset ID `fitcheck.bundled-geometric-vest`, geometry revision 1, package schema 1, `bundledMeshPackage`, role garment.
- Exact bundled path `FitCheckDevelopmentAssets/FitCheckGeometricVest.fitmesh`.
- SHA-256 `ecc2df7e57f5a12ac89f4bd16bb51d101718780ee609a72f41c8ff1b653f7f30`.
- First-party, locally owned, non-personalized, internal-development-only; capability `fitcheck.r0.metal.v1`, solid-color Lambert material.
- Right-handed metres, +Y up, +Z front, floor-centred origin, scale exactly 1. These are authored synthetic coordinates, not verified physical garment dimensions.
- Product/variant fields **still null in the resource and descriptor**. The new fictional representation permission exists only in the reviewed SKU registry; the geometry file does not assert real retailer rights.

The actual `.fitmesh` bytes are unchanged. Both vest size labels load the same 108 vertices / 108 indices / 36 triangles. No vertices are copied into procedural Swift code.

R2's actor loader still performs exact declaration validation, directory-relative pinned-FD resolution, symlink/special-file checks, a 65,536-byte read cap, SHA verification before native Foundation decoding, strict metadata/key checks, finite positions/normals, reviewed bounds, winding/topology/index checks and checked GPU sizes. Vertex/index caps remain 1,024 / 6,144 and the combined upload cap remains 45,056 bytes. There is no new parser, external URL, download, document picker, texture import or renderer engine.

Only the loader creates `RendererLoadedGarment`. The existing `RendererSceneSession.installGarment` validates that token and uploads into the original Metal objects/shader/depth pipeline. The asset hash establishes byte consistency, not a publisher signature, commercial license or physical accuracy.

## Presentation, loading and controls

The detail model remains the owner of current product and checked variant selection. `openPreview()` resolves again and captures the current immutable snapshot. Existing navigation destination ownership and `.id(preview.id)` create the correct viewer without another navigation stack. Popping preserves color/size; changing selection or reloading dismisses the old snapshot.

A bundled presentation configures its source without constructor I/O. On appearance the existing model creates a generic mannequin scene **without a procedural garment**, then starts the actual R2 loader. Loading/verified/failure status appears near the top of the product controls. There is no temporary shirt shown under a vest title.

Successful validation installs the actual file-backed mesh and approved Navy material. Product context shows the actual title/color/size label, and the existing generic/non-scan/non-fit disclosures remain. Rotation/tilt buttons, drag, Reset View, garment visibility and Reset Appearance operate on the real scene. Material is locked to the selection; appearance reset restores Navy and visibility, not another color or geometry. S/M produce identical authored geometry with different SKU context.

Product previews expose neither the Lab source chooser nor its incompatible-asset demonstration. Source-changing model commands also reject product calls, rather than relying only on hidden buttons. A missing/altered/unreadable asset leaves the mannequin where possible, clears garment buffers/identity, reports a safe error and offers retry/back. Retry uses the same approved descriptor. It cannot restore a procedural shirt as fake vest success.

Procedural product recovery is preserved: an explicitly missing procedural garment can restore only its original approved shirt. The independent Lab still switches procedural/file-backed sources, exercises an incompatible descriptor, retries, manually restores the shirt, changes Navy/Stone/Sage, toggles visibility, rotates/resets and handles foreground recovery. Its wording now distinguishes manual fixture choice from SKU authorization.

## Concurrency and resource ownership

Catalog product/variant request generations, expected-SKU guards and selection invalidation are unchanged. Pending lookups cannot authorize a preview, and late size responses cannot replace the current snapshot. Independent product detail models do not share mutable preview state.

The renderer retains one request, a scene UUID, request generation and at most one validated CPU mesh. Completion guards check cancellation, presentation/activity, generation, requested descriptor and current scene. Close cancels/releases the scene and cache while retaining only its immutable initial source choice for a later explicit reopen. A completion cannot reopen a closed scene or clear/replace a newer product's garment. Background releases GPU ownership; foreground restores only the current validated cache or starts another guarded load.

`open(isActive:)` returns an optional discardable task handle, matching existing load/retry action patterns, so async consumers/tests can await the actual operation without sleeps or a testing-only drain hook. SwiftUI ignores that handle and the model remains its owner.

Native regressions deliberately complete cancelled loaders successfully or with errors after close/replacement/background. Tests await those actual task completions, inspect disposed scenes and current buffer identity, and verify no cross-product resurrection. Real missing-file and changed-digest cases use isolated temporary bundles, never modifications to the shipped fixture. Replacing the test-owned file with reviewed bytes then retrying proves recovery through the real loader.

## Changed files

| Files | Responsibility |
| --- | --- |
| `Sources/Catalog/CatalogModels.swift`, `SyntheticCatalog.swift` | Minimal vest category and exact fictional product/SKUs |
| `Sources/Catalog/CatalogPreviewAssociation.swift` | Reviewed six-SKU association and immutable geometry-source snapshot |
| `Sources/Catalog/CatalogViews.swift` | Vest category display and neutral garment disclosure; existing navigation preserved |
| `Sources/Rendering/RendererContracts.swift`, `RendererBundledAssets.swift` | Immutable source contract and descriptor Hashable conformance; loader/validation unchanged |
| `Sources/Rendering/RendererLabModel.swift`, `RendererLabView.swift` | Automatic loading, locked recovery and shared honest status UI |
| `Tests/CatalogR3StrictValidationTests.swift` | Exact identities/options/provenance/availability/fixture policy and old/new source independence |
| `Tests/CatalogVestLifecycleTests.swift` | Delayed selection cannot replace current vest SKU/snapshot |
| `Tests/RendererAutomaticBundledPresentationTests.swift` | Real file-to-Metal buffers, source/material locks, failure/retry, stale callbacks, disposal, foreground and procedural recovery |
| `Tests/CatalogBundledDataBoundaryTests.swift` | Real SKU-to-file rendering preserves protected bytes/readiness and profile deletion independence; same geometry across S/M |
| `Tests/CatalogRepositoryTests.swift`, `RendererBundledAssetTests.swift` | Add new product identity; migrate old procedural-only negative test without weakening descriptor rejection |
| `UITests/RendererUITests.swift` | Two real-pixel end-to-end R3 scenarios, standard and accessibility XXXL |
| `README.md`, this handoff | Workflow, limitations and evidence |

The file asset, Metal scene/shader/viewport, repository implementations, profile/scanner code, launch flags, resource staging phase and privacy manifest are unchanged.

## Fresh verification and evidence

Environment: Xcode 26.5 (`17F42`), XcodeGen 2.46.0, iOS 26.5 (`23F77`) x86_64 simulators. Available devices were checked again: Debug iPhone 17 Pro `7F050083-C268-4F37-B730-C677F19A88EA`; Release iPhone 17 `D5BE86CA-76FC-4C6A-BD88-5D29FFF910F5`. Generic iPhone compilation is unsigned SDK evidence, not physical hardware testing.

Evidence lives outside Git at `/Users/anshbalusa/fitcheck-r3-artifacts`.

| Completed check | Fresh result |
| --- | --- |
| XcodeGen generation | Passed |
| Clean Debug build and complete combined unit/UI suite | **243 passed: 226 unit + 17 UI, zero failures/skips**; `debug-full-final.xcresult`, `debug-full-final-summary.json`, `debug-full-final-tests.json` |
| Targeted native integration regressions | **42 native tests passed** in `catalog-file-smoke.xcresult` |
| Normal-size catalog → file → Metal pixel scenario | Passed in that same run |
| Initial largest-text scenario | Real vest rendered/rotated/reset; test later failed to locate virtualized M after returning to details; that run totals 43 passed / 1 failed |
| Corrected largest-text complete catalog/preview/navigation scenario | **1 passed, zero failures/skips**; `large-text-navigation-final.xcresult` |
| Final-source unsigned generic-iPhone Debug compilation | Passed; `iphone-final.xcresult` |
| Final-source normal Release simulator build | Passed without testability override; `release-final.xcresult` |
| Final-source relevant Release isolation suite | **12 passed, zero failures/skips**; `release-isolation-final.xcresult` |
| Actual bundle inspection | No `.fitmesh` or `FitCheckDevelopmentAssets` directory in normal Release |
| Actual binary/privacy/digest inspection | 31 development markers present in Debug, absent from Release; all four manifests correct; source and both Debug bundled asset digests match; `binary-privacy-resource-verification.json` |

The final complete run preserves R2's 225-test coverage, with the procedural-only authorization test migrated for the deliberately extended contract, and adds **16 native + 2 real-pixel UI tests**. All execute without failures/skips; the separate Release suite remains 12/12. Native model/buffer tests are not substituted for the UI rendering proof.

The first compile exposed an untyped optional fixture test array; its explicit descriptor type corrected the test harness. Focused pre-repair execution then reproduced two failures in `integration-regressions-before-repair.xcresult`: the new source lock had accidentally disabled original procedural-product restoration, and the R2 negative test still assumed all catalog products were procedural. Restoration was repaired; the existing negative test now retains its original exact-descriptor rejection and all original T-shirt cases while the new explicit vest association receives separate strict coverage. No arbitrary bundled asset became procedural or SKU-authorized.

The largest-text diagnostic hierarchy showed Size above the scroll position but no instantiated lazy size buttons; the helper had scrolled downward when the target did not exist. The return/reselection path now navigates through the persistent Size section header before choosing M. That correction passed vest S/M interactions, then exposed the same helper assumption when returning from the last product to an uninstantiated first product cell. Product selection now performs a bounded upward search to the collection landmark before the existing downward search. The completed `large-text-navigation-final.xcresult` passes the entire scenario. No button is hidden, text reduced or hit-target/pixel assertion relaxed; the app's adaptive size grid and lazy collection remain unchanged. Generic product disclosure now says garment rather than incorrectly limiting the new vest flow to a shirt. The passing synthetic capture is in `large-text-final-visuals/`.

### Actual simulator evidence

The normal scenario uses an actual procedural Lab viewport as a negative pixel control, then enters the catalog, selects vest Navy S and waits for both verified source identity and a distinct colored file-backed silhouette. It exercises drag/depth, camera reset to reference pixels, hide/show/appearance reset, background/foreground, return and M selection, identical S/M geometry pixels, repeated reentry, switching to Everyday's original procedural shirt, Cream rejection and switching back to a fresh vest S context. Largest text repeats the actual product flow, rotation/reset/visibility, locked controls, M selection and safe catalog/hub return.

Synthetic Navy S, rotated vest, Navy M, original procedural product and largest-text images from `smoke-visuals/` were exported and inspected. Tests inspect real viewport pixels and the viewport's actual scene asset identity; a state Boolean or label alone is not rendering proof. Results/captures are not committed and contain no personal scan content.

Native tests compare every actual Metal vertex/normal/index against the decoded reviewed file and check requested buffer lengths. Appearance/visibility changes retain the uploaded buffers. Three explicit same-model close/reopen cycles verify released buffer references and correct source recreation; R2's existing install/clear/dispose coverage remains part of full regression. Protected-profile scenarios render S/M through the real catalog detail and loader while verifying missing, pending, unsupported-schema and corrupt states and bytes remain unchanged. Those tests establish state/data invariance; source dependency separation, not byte equality alone, establishes no profile/scanner dependency.

### Release, privacy and rights

Actual production root inspection shows only executable, Info.plist, PkgInfo, Assets.car, two app icons and PrivacyInfo.xcprivacy. Recursive resource checks and the existing Release bundle enumeration test verify no development mesh ships. Positive Debug/negative Release markers include the new geometry-source type, concept title and both exact SKU strings, plus the R0–R2 scanner/catalog/renderer/loader controls. `#if DEBUG` is not treated as the only evidence.

Built Debug simulator, Debug iPhone, normal Release and Release-test manifests retain exactly boot time `35F9.1`, UserDefaults `CA92.1`, and file metadata `C617.1`; tracking remains false and collection empty. R3 introduces no new required-reason API. Catalog-triggered loading accesses the same app-owned bundled file metadata already covered by R2's `fstat` policy. No timestamps are exported. This is not App Store privacy approval.

The unchanged vest was authored first-party in-project for synthetic development. R3 grants only this fictional internal association, not a real product construction claim or external-model license. Future retailer assets require independent authorization, exact product/variant association, commercial display/distribution rights, revision/integrity, coordinate/material compatibility and an approved bounded ingestion policy. No download, remote importer, account, checkout, telemetry or body-data dependency is added.

### Resource and hardware limits

The mesh's requested vertex/index content remains 3,456 + 216 = 3,672 bytes; this is not physical GPU allocation size. Parsing remains on the existing bounded loader actor, not the SwiftUI main actor. Native ownership tests and repeated real UI navigation are observed evidence, not a sustained-memory plateau or leak-free guarantee. No R3 FPS, thermal or prolonged memory measurements are claimed; R2's unsuccessful Instruments trace is historical, not a new result.

Physical GPU/resource behavior, prolonged memory/thermal performance, oldest iOS runtime and manual VoiceOver remain unverified. LiDAR Segment 1B remains **NOT RUN**. Real front/side scanning, personalized geometry and physical garment sizing/fit remain blocked or unsupported; simulator success does not change those limits.

## Reproduction

Run from the repository; use unused result paths when repeating. Confirm available simulator IDs rather than assuming these persist.

```sh
ARTIFACTS=/Users/anshbalusa/fitcheck-r3-artifacts
xcodegen generate
xcodebuild -project FitCheck.xcodeproj -scheme FitCheck -configuration Debug \
  -destination 'platform=iOS Simulator,id=7F050083-C268-4F37-B730-C677F19A88EA' \
  -derivedDataPath "$ARTIFACTS/DebugDerived" \
  -resultBundlePath "$ARTIFACTS/debug-full-final.xcresult" \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO clean build test -quiet
xcodebuild -project FitCheck.xcodeproj -scheme FitCheck -configuration Debug \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath "$ARTIFACTS/iPhoneDerived" \
  -resultBundlePath "$ARTIFACTS/iphone-final.xcresult" CODE_SIGNING_ALLOWED=NO build -quiet
xcodebuild -project FitCheck.xcodeproj -scheme FitCheck -configuration Release \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$ARTIFACTS/ReleaseDerived" \
  -resultBundlePath "$ARTIFACTS/release-final.xcresult" CODE_SIGNING_ALLOWED=NO build -quiet
```

Release test selectors are the R2 route/privacy/resource suite: `AvatarFeatureIsolationTests`, `CatalogIsolationTests`, `InternalDevelopmentRouteTests`, `IntegrationPrivacyManifestTests`, `RendererDevelopmentResourceIsolationTests`, `AvatarPilotUITests`, catalog normal-launch isolation, integration Release flag isolation, and the Release `RendererUITests`. Use the separate `ReleaseTestDerived` directory and `ENABLE_TESTABILITY=YES` **only** for that test artifact, never for the normal production build. `xcresulttool get test-results summary/tests` provides actual counts; export synthetic screenshots separately. Do not concurrently extract two reports from the same result bundle: the installed tool can race while materializing its SQLite cache.

## Verdict

**GO for the exact synthetic internal catalog-to-file-backed association, pending draft-PR review.** The selected vest SKU resolves to the reviewed R2 descriptor, loads the unchanged actual file, uploads verified Metal buffers and renders a distinct controllable vest. Both S/M use identical geometry; old procedural previews and independent Lab behavior remain operational. Final clean Debug 243/243, Release isolation 12/12, SDK builds, actual artifact checks and simulator/accessibility verification pass.

**NO-GO for commercial release, external retailer assets, arbitrary imports, personalized geometry, physical sizing or fit.** No hardware blocker or external asset-rights requirement is resolved by a successful fictional software integration.
