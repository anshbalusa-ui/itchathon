# Segment R2 — bounded bundled garment asset pipeline

## Scope and baseline

Branch: `feature/bundled-3d-asset-pipeline-r2`.

Base and intended draft-PR target: `feature/catalog-3d-preview-r1`, PR #14, commit `701ffcf1f8c7eec4fcc89db1262e6dc7bf756d51`. The local worktree was clean, local/remote R1 heads matched after fetch, PR #14 remained an open draft, and no newer PR superseded it. A new branch was created without merging or rewriting the R1/R0/integration stack. The baseline's 194 Debug and 11 Release tests are historical results, not R2 evidence.

This segment adds one reviewed, local, first-party mesh package to the existing native Metal renderer. It does not add a general importer, retailer asset authorization, personalized geometry, size-specific meshes, cloth physics or fit prediction. Existing R1 Navy/Sage SKU associations continue using the original procedural shirt; the bundled vest is deliberately unassociated with every catalog product.

## Graphics and format decision

Retain R0's MetalKit/Metal scene, indexed meshes, depth testing, Lambert shader, camera/orbit, and scene ownership. RealityKit/SceneKit/web rendering are not introduced. R0's documented simulator-driver findings remain the reason not to revisit the engine here.

The supported format is a narrowly specified **version-1 JSON mesh package**, extension `.fitmesh`, decoded by native Foundation `JSONDecoder`. It contains one triangle mesh, explicit position/normal scalars, indices and a fixed metadata header. There is no arbitrary OBJ, USDZ or other asset-format support.

The installed iOS 26.5 Model I/O headers (`MDLAsset.h`, `MDLMesh.h`, `MDLSubmesh.h`) were inspected. Model I/O offers URL-based import and framework-created mesh/buffer/submesh objects before application validation. That is useful for future conversion, but unnecessary for this single bounded, texture-free fixture. A native JSON decoder plus an explicit package contract avoids an OBJ/material/sidecar parser and a broad runtime import surface. APIs used by the new path are compatible with the project's iOS 17 deployment target; the iOS 17 runtime itself was not exercised.

Limitations: no polygon triangulation, skeletal animation, skinning, embedded scenes, texture decoding, material libraries, morph targets, arbitrary submeshes, external references or automatic coordinate conversion. New package identities/revisions require an explicit code/fixture review rather than filename discovery.

## First-party file and provenance

`DevelopmentAssets/FitCheckGeometricVest.fitmesh` is actual separately authored resource data, not a call to the procedural Swift shirt function. It was authored in-project from simple mathematical rings and triangles for this segment: a faceted sleeveless shell with a flared open hem, V-cut front neckline, higher rear edge and two folded front lapels. It has no person-specific data, logos, downloaded model, external texture or third-party source asset.

The package has **108 face-duplicated vertices, 108 indices and 36 triangles**, and is 16,645 bytes. Flat normals deliberately expose the faceted shape under rotation. Its silhouette is visibly different from the procedural sleeved shirt.

- Asset ID: `fitcheck.bundled-geometric-vest`; geometry revision: `1`.
- Package format: `fitcheck.mesh-json`; schema: `1`; asset type: `bundledMeshPackage`; role: `garment`.
- Exact resource: `FitCheckDevelopmentAssets/FitCheckGeometricVest.fitmesh` inside the application bundle.
- Source/provenance: `bundledFixture` / `firstPartyFixture`; local ownership required; personalization false.
- Approved usage policy: `internalDevelopmentOnly`. This is the renderer's allowed-use policy, not a claim of a third-party license, retailer permission, commercial asset approval or a new general repository license.
- Product and variant association: both explicitly null.
- Renderer capability: `fitcheck.r0.metal.v1`; material model: `solidColorLambert`.
- Expected SHA-256: `ecc2df7e57f5a12ac89f4bd16bb51d101718780ee609a72f41c8ff1b653f7f30`.

The hash pins reviewed bytes and metadata. It is not a signature, a trusted external publisher mechanism, a commercial-rights grant or a SKU authorization.

## Coordinates and geometry limits

Coordinates are right-handed, metres, +Y up, +Z forward, floor-centred origin, scale exactly 1. These are renderer coordinates and synthetic authoring dimensions, **not verified garment or body measurements**. No selected S/M/L label changes geometry.

| Boundary | Enforced limit |
| --- | --- |
| File bytes before decoding | 65,536 maximum |
| Vertex count | 1–1,024 |
| Index count | 3–6,144, divisible by 3 |
| GPU upload byte calculation | Checked multiplication/addition; 45,056 maximum combined vertex/index bytes |
| Vertical position | 0 through 1.8 metres |
| Horizontal position radius | At most 0.4 metres |
| Normal length | Unit length within 0.001 |
| Triangle cross-product squared length | Greater than `1e-10` |
| Triangle winding versus each vertex normal | Dot product with normalized face normal greater than 0.9 |
| Reviewed bounds | Min `(-0.29, 0.84, -0.16)`, max `(0.29, 1.43, 0.215)`, tolerance `1e-5` |

All positions and normals must be finite; index references must be in range before UInt16 conversion. Empty, excessive, degenerate, incorrectly wound or non-triangle data fail. Bounds must have three nonzero extents and match the reviewed fixture. Unknown package/vertex keys, metadata, versions, roles, units, scale, identities, revisions, capabilities, materials, submesh counts and topology are rejected, not repaired.

Winding validation checks consistency with unit vertex normals; the reviewed digest pins the intended whole shape. This open shell is not a watertight solid, and the validator is not a general self-intersection, outward-volume or physical-garment-quality checker.

## Resolution, decoding and GPU boundary

1. `RendererBundledAssetDescriptor.validate()` accepts only the exact registered vest declaration. Resource name, extension, digest, role, revision, provenance, rights, coordinates and capability cannot be substituted by a title or an arbitrary descriptor.
2. `RendererBundledAssetLoader` is an actor. It resolves the app-owned bundle resource root, opens only the registered development directory and leaf using directory-relative POSIX access, and rejects symlinks with `O_NOFOLLOW`. `O_NONBLOCK` prevents special files such as FIFOs from blocking a read.
3. `fstat` on the pinned open descriptor requires a regular file with a nonnegative bounded size. Reads use a bounded buffer, detect growth past the cap, handle interruption, and close descriptors on every path. There is no document picker, arbitrary URL, download or directory crawl.
4. SHA-256 is verified **before JSON decoding**. Foundation decoding can allocate CPU objects before element-count validation, so the pre-decode byte cap and exact reviewed digest are important trust boundaries. This decoder is not exposed to arbitrary user or remote files.
5. The decoded package validates metadata, checked buffer sizes, finite scalars, normals, winding, triangle indices and reviewed bounds before creating the renderer mesh.
6. Only the loader can construct `RendererLoadedGarment`; its initializer is file-private. The validated immutable token crosses back to the presentation model.
7. `RendererSceneSession.installGarment` validates that token's descriptor again and creates the existing `RendererRenderObject`/Metal vertex and index buffers. It does not introduce another renderer or low-level catalog coupling.

The original `RendererAssetDescriptor.validate(for:)` procedural-fixture rules remain strict and unchanged. A bundled descriptor cannot masquerade as either original fixture. Adding the explicit bundled asset type does not make the original validator accept other assets.

## State, lifecycle and recovery

The Lab presentation alone enables asset selection. Catalog preview presentations do not expose the controls, and their models reject attempted lab asset changes.

Open the Debug integrated hub → **3D Renderer Lab** → **Garment asset demonstration**. Deliberately choose **Procedural shirt** or **Bundled geometric vest**. The generic mannequin, real rotation/tilt buttons and drag, Reset View, show/hide, Navy/Stone/Sage and Reset Appearance remain available. Materials and visibility change the existing render object without re-uploading mesh buffers.

Loading clears the old garment immediately. A load failure keeps the mannequin but displays **Garment asset unavailable**, a safe explanation, **Retry garment asset**, and explicit source choices. There is no phantom garment or silent procedural fallback under a loaded-file label. **Check incompatible asset** exercises a genuinely unregistered descriptor through the real policy; retry rejects it again, while choosing the reviewed vest or explicitly returning to the procedural shirt recovers. Missing-file and malformed-file cases are also exercised by native tests. Raw paths and parser diagnostics are not displayed.

The model owns one asynchronous request and at most one validated CPU garment cache. Request generation, scene UUID, descriptor, presentation/activity and cancellation guards reject late results. Manual procedural return cancels/invalidate-generates before changing state. A failed reload clears the previous CPU cache, so foreground recovery cannot resurrect an older garment. Close clears the request/cache and disposes the scene; background cancels work and releases GPU ownership. Foreground rebuilds one scene, reusing only the current validated CPU cache or starting a fresh guarded request. A late completion cannot reopen a dismissed scene.

`RendererViewport` observes the presentation model so accessibility values track the actual session garment, its visibility and material, including the no-garment failure state. Source choices expose labels and selection values rather than color alone. Largest accessibility XXXL controls/errors remain reachable through the existing scroll layout; rotation does not require a gesture.

## Changed files and responsibilities

| File | Responsibility |
| --- | --- |
| `DevelopmentAssets/FitCheckGeometricVest.fitmesh` | First-party reviewed file-backed mesh and metadata |
| `Sources/Rendering/RendererBundledAssets.swift` | Exact registry, safe FD reads, digest, native decoding, metadata/geometry limits, validated token and recoverable errors |
| `Sources/Rendering/RendererContracts.swift` | Explicit bundled type, Sendable scalar contracts and Lab-only asset-selection capability |
| `Sources/Rendering/RendererProceduralAssets.swift` | Sendable mesh/vertex transfer; original procedural geometry unchanged |
| `Sources/Rendering/RendererSceneSession.swift` | Validated GPU installation, source identity, clear/dispose and safe procedural restoration |
| `Sources/Rendering/RendererLabModel.swift` | Async loading, generation/scene ownership, cache invalidation, retry and lifecycle |
| `Sources/Rendering/RendererLabView.swift` | Accessible source choices, real failure state and explicit recovery |
| `Sources/Rendering/RendererViewport.swift` | Observed presentation and accurate actual-scene accessibility value |
| `Sources/Support/PrivacyInfo.xcprivacy` | Existing reasons preserved; justified file-metadata reason added |
| `Tests/RendererBundledAssetTests.swift` | Real-file metadata, geometry, arithmetic and malformed-data regressions |
| `Tests/RendererBundledFileBoundaryTests.swift` | Missing, symlink, special-file, size, integrity, registry and cancellation boundaries |
| `Tests/RendererBundledLifecycleTests.swift` | Real Metal buffers, ownership, stale completions, failures, recovery and catalog isolation |
| `Tests/RendererDevelopmentResourceIsolationTests.swift` | Actual Release bundle contains no development directory or `.fitmesh` resource |
| `Tests/IntegrationPrivacyManifestTests.swift` | Complete three required-reason declarations plus no tracking/collection |
| `UITests/RendererUITests.swift` | Two real GPU/pixel, navigation, lifecycle and accessibility scenarios; Release control absence |
| `project.yml` | Debug-only resource staging, not ordinary unconditional Xcode resources |
| `README.md` | Discoverable Lab workflow and limitations |
| `Docs/RENDERER_R2_ASSET_PIPELINE_HANDOFF.md` | This handoff |

No scanner, profile repository, catalog repository or SKU-association registry is changed. No new package dependency, service, credential or personal data is introduced.

## Production isolation and privacy

The fixture lives outside `Sources`; XcodeGen's `fileGroups` only makes it visible in the project. A declared post-build phase copies exactly this file into `FitCheckDevelopmentAssets` only for `Debug`. Other configurations remove only that phase's own generated leaf and empty directory; unexpected contents fail rather than being recursively deleted. Environment-variable dumping is disabled. The loader/UI/types remain `#if DEBUG`. See [XcodeGen's build-script and file-group specification](https://github.com/yonaskolb/XcodeGen/blob/2.46.0/Docs/ProjectSpec.md).

Actual artifact inspection found all **27** existing/new development markers in Debug and none in the normal Release executable. Markers include scanner/catalog/preview types, renderer classes/shaders, bundled loader/token/package types, asset identity and Lab controls. The direct `_fstat` symbol is present in Debug and absent from normal Release. Release's complete app root contains only the executable, Info.plist, PkgInfo, Assets.car, two app icons and PrivacyInfo.xcprivacy; recursive `.fitmesh`/development-directory checks found nothing. The Release test also enumerates the actual bundle rather than trusting source conditionals. Source, simulator Debug and iPhone Debug fixture digests match exactly.

Apple lists `fstat` under the File Timestamp required-reason API category even when only file size/type metadata is used. The shared manifest therefore adds **`NSPrivacyAccessedAPICategoryFileTimestamp: C617.1`** for app-owned bundled-file metadata. No timestamps are used; metadata is not exported or collected. Existing **System Boot Time `35F9.1`** and **UserDefaults `CA92.1`** remain intact. Tracking remains false and collected-data declarations remain empty. The shared manifest retains the additional reason in Release even though the new loader/direct call are compiled out. This is a justified declaration change, not a claim that the manifest is unchanged or App Store-approved. [Apple's category and approved-reason policy](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype).

All four built manifests—simulator Debug, unsigned iPhone Debug, normal Release and Release test build—were parsed and verified. The pipeline has no profile access, scanner initialization, camera permission path, scan data, persistence, telemetry or networking. The only new persisted geometry is this non-personal, first-party Debug fixture.

## Fresh verification — 2026-10-21

Environment: Xcode 26.5 (`17F42`), XcodeGen 2.46.0, installed iOS 26.5 (`23F77`) x86_64 simulators. Freshly checked Debug device: iPhone 17 Pro `7F050083-C268-4F37-B730-C677F19A88EA`; Release isolation: iPhone 17 `D5BE86CA-76FC-4C6A-BD88-5D29FFF910F5`. Generic device compilation is unsigned SDK verification, not a physical-device run.

Evidence is outside Git under `/Users/anshbalusa/fitcheck-r2-artifacts`.

| Check | Fresh completed evidence |
| --- | --- |
| XcodeGen generation | Passed with final resource staging configuration |
| Clean Debug build and complete combined unit/UI suite | **225 passed: 210 unit + 15 UI**, zero failures/skips; `debug-full-final.xcresult`, `debug-full-final-summary.json`, `debug-full-final-tests.json` |
| New native validation/file/lifecycle tests | 29 passed in `asset-smoke.xcresult`; this intermediate 31-test run also had one passing largest-text UI scenario and one failed normal UI scenario, corrected below |
| Corrected actual asset UI scenario | 1 passed, zero failures/skips; `asset-accessibility-corrected.xcresult` |
| Unsigned generic-iPhone Debug SDK build | Passed; `iphone-debug.xcresult` |
| Normal production Release simulator build | Passed without testability override; `production-release.xcresult` |
| Release routing/privacy/resource-isolation suite | **12 passed: 8 unit + 4 UI**, zero failures/skips; `release-isolation.xcresult` |
| Binary, resources and privacy inspection | Passed; `final-binary-privacy-resource-verification.json`, `release-test-details.json` |

The final complete execution preserves all 194 R1 tests and adds 29 native security/geometry/GPU/lifecycle tests plus two simulator UI tests. The new Release-only bundle-resource test adds one check to the prior 11-test Release coverage. Native object/state tests are not substituted for the separate real-pixel UI proof.

Native tests exercise the actual bundled file, SHA and bounded filesystem access, not only mocks. Invalid fixtures are small deterministic test data; Int.max arithmetic is tested without allocating it. Test-only IEEE number decoding reaches finite-value validation; production JSON decoding does not accept NaN/Infinity strings. Metal tests inspect actual buffer lengths/content, unchanged buffers under material/visibility changes, repeated installation/removal and released buffer ownership. Deferred loaders deliberately ignore cancellation to prove late-result guards.

Development iterations reproduced an incorrectly transcribed initial digest, acceptance of unknown JSON keys, a late result overriding manual procedural return, and old CPU cache resurrection after a failed reload. The fixed registry bytes, explicit key validation, request invalidation and cache clearing resolve these. One test observer overfulfilled an XCTest expectation during a second matching lifecycle transition; it now consumes the first intended transition without weakening assertions. The first full asset smoke found stale viewport accessibility values even though pixels correctly showed the vest/failure; making the UIKit bridge observe the model fixed the actual accessibility defect. The corrected normal UI scenario passed. Existing assertions, pixel thresholds and meaningful coverage were not deleted, skipped or relaxed.

### Actual simulator visual evidence

The normal asset scenario enters from the integrated hub, observes the procedural shirt, loads the real vest, and requires colored viewport pixels **and** a distinct silhouette before proceeding. It then exercises drag, perspective/depth change, reset-to-reference pixels, hide/show, Sage rendering, button rotation, background/foreground, real incompatible-descriptor rejection, mannequin-only error pixels, retry, explicit procedural recovery, repeated switching, back/reentry and an independent R1 Navy catalog preview with no Lab asset controls.

The largest-text scenario uses accessibility XXXL and exercises file loading, visible Sage pixels, rotation, both resets, visibility, reachable error/retry/manual recovery and hub return. Real captured Navy/front, rotated, no-garment-error and largest-text Sage images were inspected. `corrected-visuals/` contains the passing normal scenario's three synthetic screenshots; `smoke-visuals/` contains the largest-text and earlier diagnostic captures. Screenshots and result bundles remain outside the repository and contain only synthetic app content.

These pixels plus actual parsed mesh/GPU buffer tests establish file-backed rendering. A selected-asset Boolean or loaded label alone is not accepted as visual proof.

### Resource and performance observations

The imported mesh's actual Metal buffer lengths are **3,456 vertex bytes + 216 index bytes = 3,672 requested upload bytes**. This is logical buffer content, not the driver's full physical allocation. Tests run eight install/clear/dispose cycles and verify every imported vertex/index buffer reference is released. Material/visibility updates preserve buffer identity. Existing scene/view weak-ownership tests remain part of regression coverage. One validated CPU mesh is retained only for the current selected file; parsing/hashing/read work runs on the loader actor, not the SwiftUI main actor.

A bounded native `footprint -p` sampler captured actual simulator process observations during the targeted UI run, with screenshots identifying activity and PIDs kept separate:

| Process | Observation interval | Reported footprint range |
| --- | --- | --- |
| FitCheck PID 22275 | Sampler seconds 0–103 | 59–61 MB |
| FitCheck PID 22514 | Sampler seconds 111–239, including cold startup and changing UI/scenes | 30–53 MB |

`asset-profile-observations.json`, `asset-profile-*.txt` and synthetic screenshots retain the raw observations. These are short, coarse, pre-final-accessibility-observation-fix samples, not a steady-state plateau or a leak-free verdict. Startup/scene/UI changes and process restarts must not be combined into a growth claim. An Allocations Instruments attempt attached to FitCheck PID 24386 but did not complete within the 120-second command deadline; it produced only an incomplete trace, so no allocation/leak result is claimed from it. No FPS, thermal, physical GPU-memory or sustained-performance claim is made.

## Reproduction commands

Use fresh result paths on another run; the paths here identify this session's evidence.

```sh
ARTIFACTS=/Users/anshbalusa/fitcheck-r2-artifacts
DEBUG_SIM=7F050083-C268-4F37-B730-C677F19A88EA
RELEASE_SIM=D5BE86CA-76FC-4C6A-BD88-5D29FFF910F5
xcodegen generate

xcodebuild -project FitCheck.xcodeproj -scheme FitCheck -configuration Debug \
  -destination "platform=iOS Simulator,id=$DEBUG_SIM" \
  -derivedDataPath "$ARTIFACTS/DebugDerived" \
  -resultBundlePath "$ARTIFACTS/debug-full-final.xcresult" \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO clean build test -quiet

xcodebuild -project FitCheck.xcodeproj -scheme FitCheck -configuration Debug \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath "$ARTIFACTS/iPhoneDerived" \
  -resultBundlePath "$ARTIFACTS/iphone-debug.xcresult" \
  CODE_SIGNING_ALLOWED=NO build -quiet

xcodebuild -project FitCheck.xcodeproj -scheme FitCheck -configuration Release \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$ARTIFACTS/ReleaseDerived" \
  -resultBundlePath "$ARTIFACTS/production-release.xcresult" \
  CODE_SIGNING_ALLOWED=NO build -quiet

xcodebuild -project FitCheck.xcodeproj -scheme FitCheck -configuration Release \
  -destination "platform=iOS Simulator,id=$RELEASE_SIM" \
  -derivedDataPath "$ARTIFACTS/ReleaseTestDerived" \
  -resultBundlePath "$ARTIFACTS/release-isolation.xcresult" \
  -parallel-testing-enabled NO \
  -only-testing:FitCheckTests/AvatarFeatureIsolationTests \
  -only-testing:FitCheckTests/CatalogIsolationTests \
  -only-testing:FitCheckTests/InternalDevelopmentRouteTests \
  -only-testing:FitCheckTests/IntegrationPrivacyManifestTests \
  -only-testing:FitCheckTests/RendererDevelopmentResourceIsolationTests \
  -only-testing:FitCheckUITests/AvatarPilotUITests \
  -only-testing:FitCheckUITests/CatalogUITests/testNormalLaunchAndReleaseOptInRemainIsolated \
  -only-testing:FitCheckUITests/IntegrationUITests/testInternalRouteFlagsRemainLegacyInRelease \
  -only-testing:FitCheckUITests/RendererUITests \
  ENABLE_TESTABILITY=YES CODE_SIGNING_ALLOWED=NO test -quiet
```

`ENABLE_TESTABILITY=YES` is only for the separate Release test artifact, never the normal production build. `xcresulttool get test-results summary/tests` gives executed counts; `xcresulttool export attachments` exports captures. `strings -a` and `nm -u` inspect real binaries; `plutil` parses actual bundled manifests; SHA-256 compares the authored and copied files.

## Future real assets and remaining limits

A future asset needs a separately reviewed identity/revision and geometry policy, authorized source and distribution rights, validated units/origin/scale/normals/materials/topology, bounded conversion/import, renderer capability and integrity/publication strategy. A retailer garment additionally needs explicit retailer authorization and exact product/variant/color association. A first-party bundle license or hash does not establish any of those retailer relationships. Importing arbitrary USDZ/OBJ, downloading meshes or adding account/cloud services is separate, unauthorized work.

An approved personalized avatar would need genuinely available geometry, appropriate ownership/privacy/consent, a compatible renderer and validated scan provenance; structurally valid profile metadata or a generic mannequin does not supply this. File coordinates do not establish real garment dimensions, fabric behavior, clearance, drape or physical fit.

Physical-device GPU/resource/lock behavior, oldest iOS runtime, manual VoiceOver, sustained memory/thermal behavior and a successful Instruments allocation/leak trace remain unverified. Segment 1B real LiDAR validation remains **NOT RUN** and blocks scan-derived personalized geometry approval.

## Verdict

**GO for the bounded internal-development garment asset pipeline, pending PR review.** One exact reviewed first-party file loads through the validated CPU boundary into real Metal buffers and visibly renders; final clean Debug 225/225, Release isolation 12/12, both SDK builds and actual bundle/binary/privacy checks pass. Existing R1 associations remain unchanged.

**NO-GO for commercial release, arbitrary production-file ingestion, real retailer assets, personalized scan-derived geometry or physical fit.** The successful synthetic file path does not authorize any of those capabilities or resolve the hardware/performance limitations above.
