# Segment R0 — native 3D rendering foundation

## Delivery baseline and decision

- Source branch: `feature/3d-renderer-foundation-r0`.
- Parent/base: `integration/avatar-scanner-catalog-20261020` at **`1afe034d7376f16e6c7e993f95931ace45a0d692`** (draft PR #12).
- Starting local and fetched remote heads matched; the worktree was clean, with no interrupted Git operation. No old `/tmp` rendering implementation was recovered or reused.
- Target for the R0 draft PR is the integration branch, not `main`. No dependency PR was merged or duplicated.
- **GO for the generic internal Renderer Lab, pending review. NO-GO for personalized avatars, scan accuracy, physical garment fit, virtual try-on, or commercial release.**

The recovered 149-test baseline was historical starting evidence for this assignment. The final results below are newly executed R0 results, not a sum of earlier PR totals.

## Graphics technology: MetalKit and Metal

The final implementation uses an actual `MTKView`, indexed vertex/index buffers, a depth buffer, perspective projection, model transforms, and first-party Metal vertex/fragment shaders. SwiftUI hosts the view through `UIViewRepresentable`. Rendering is on demand (`isPaused` plus `enableSetNeedsDisplay`), not a continuous application-owned display loop.

The installed environment was Xcode 26.5 (`17F42`), XcodeGen 2.46.0, x86_64 macOS host, and iOS 26.5 (`23F77`) simulators. The deployment minimum remains **iOS 17.0**. Installed SDK interfaces were inspected rather than relying on an old example.

### Why not the initially preferred RealityKit

RealityKit was implemented and exercised first. The installed SDK supports non-AR `ARView(frame:cameraMode:automaticallyConfigureSession:)` on the existing deployment minimum; SwiftUI `RealityView` requires iOS 18. Initial RealityKit screenshots genuinely rendered, rotated, hid the garment, and changed material. Those early successes were not treated as final reliability proof.

Later actual simulator runs stalled, including a clean combined run with **166 passed and 3 renderer UI failures**. A second simulator and explicit reduced rendering effects did not resolve it. Diagnostics captured:

- `SimMetalHost` `EXC_BAD_ACCESS` in `AppleIntelKBLGraphicsMTLDriver` → `SamplerStage::bindSamplerToTexture`.
- The app main thread blocked in `ARView.commonRenderCallback` → CoreRE `waitForIdleInternal`; its render thread waited in Metal `waitUntilScheduled`.

R0 therefore selects a smaller supported Apple-native API that works in this environment: **direct MetalKit mesh rendering without texture samplers, RealityKit's scene engine, or AR capture**. The RealityKit implementation was removed, not kept as a fallback or compatibility layer. The final tests use the same real Metal renderer on simulator and iPhone SDK builds. No simulator-only fake scene, image, or prerecorded animation exists. This is an evidence-backed backend choice, not a claim that FitCheck repaired Apple's graphics driver.

MetalKit has stable iOS support and avoids introducing deprecated SceneKit code or a third-party engine. The tradeoff is ownership of a small explicit shader and camera implementation. It is not a general-purpose scene engine, USDZ importer, or physically based material system.

## Source responsibilities

| File | Responsibility |
| --- | --- |
| `Sources/Rendering/RendererContracts.swift` | Finite scene/framing policy, bounded orbit, appearance, exact registered asset compatibility and failure categories |
| `Sources/Rendering/RendererProceduralAssets.swift` | Plain indexed mesh/vertex data and authored mannequin, open garment shell, and color fixtures |
| `Sources/Rendering/RendererSceneSession.swift` | Metal device/queue/pipeline/depth setup, two independently owned draw objects, camera/model matrices, on-demand drawing, GPU failure reporting and disposal |
| `Sources/Rendering/RendererLabModel.swift` | One presented scene owner, controls, retry, garment recovery, background/foreground and stale-completion isolation |
| `Sources/Rendering/RendererViewport.swift` | Native view/drag bridge; weak gesture coordinator and accessible scene description |
| `Sources/Rendering/RendererLabView.swift` | Scrollable controls, persistent viewport, accessible alternatives, explicit errors and truthful fixture descriptions |
| `Sources/Development/InternalDevelopmentHub.swift` | Add the native **3D Renderer Lab** destination to existing navigation ownership |
| `Tests/RendererContractTests.swift` | Invalid/unknown asset and finite configuration/orbit boundaries |
| `Tests/RendererMeshTests.swift` | Actual 3D topology, nondegenerate outward triangles, finite unit normals, floor/forward convention and open boundary loops |
| `Tests/RendererSceneTests.swift` | Real GPU resources, transforms/framing, material/visibility updates without replacing buffers, asset recovery, resize extremes and disposal |
| `Tests/RendererLabModelTests.swift` | Real scene ownership, retry, background release/recreation, appearance/view reset and stale GPU completion rejection |
| `UITests/RendererUITests.swift` | Actual pixel-verified 3D interactions, four exit/reentry cycles, background recovery, other modules and largest accessibility text; Release rejection |
| `Tests/InternalDevelopmentRouteTests.swift` | Preserve deterministic routing and reject invented standalone renderer launch aliases |
| `UITests/IntegrationUITests.swift` | Extend existing Release assertions to reject the renderer destination and viewport |
| `README.md` | Current development entry instructions and generic-versus-personalized distinction |

All rendering implementation, shader source, meshes, and the hub remain behind `#if DEBUG`. `project.yml`, scanner algorithms/lifecycle, protected profile storage, the avatar readiness contract, catalog identity checks, legacy preferences and the privacy manifest were not changed.

## Actual geometry and materials

### Mannequin

An anonymous, faceless geometric fixture built from ellipsoids and cuboids: head, neck, torso, waist connection, pelvis, two arms, separated legs, and forward-projecting feet. Sphere geometry is reused while constructing the ellipsoid parts; normals account for their nonuniform scales. Parts are combined into one indexed mannequin mesh/draw object. This is authored synthetic geometry, not a measured person or body reconstruction.

### Garment

A **separate indexed 3D draw object**, not baked into the mannequin. Its torso is an uncapped elliptical-ring shell with an open hem and neckline, plus a raised open collar and simple short-sleeve volumes. It is a stylized T-shirt-like visualization fixture. The sleeve volumes are closed primitives; this is not a watertight sewn garment, fabric pattern, thickness model, drape, clearance measurement or size specification.

Navy, Stone and Sage change the actual garment fragment color. The mannequin draw object's color and buffers remain independent. One neutral directional light plus ambient illumination is implemented by the Lambert shader. No textures, UV asset pipeline, PBR, shadows, cloth physics, skinning or deformation is claimed. There are two indexed draw calls when the garment is visible and one when hidden.

## Coordinate, camera and compatibility conventions

- World units: **metres**; right-handed coordinates; **+Y up**, mannequin front **+Z**.
- Mesh root: floor-centred; feet meet the synthetic floor. Fixture scale is 1. These units describe the authored fixture, not a shopper's body measurements.
- Orbit pivot/camera target: `(0, 0.9, 0)` in the standard configuration. Transform is `T(pivot) * yawY * pitchX * T(-pivot)`.
- Standard camera: positive Z looking at the pivot, distance 3.4, vertical field of view 45 degrees, near 0.1 and far 20. Projection uses right-handed Metal depth `[0, 1]`.
- Yaw wraps; pitch clamps to ±π/8. NaN/infinite input cannot enter a transform. Very large finite deltas remain finite. Reset View returns to yaw π/8 and pitch 0; it does not reset garment appearance.
- Configuration validation reserves conservative framing and near-plane clearance. Drawable aspect changes update projection and conservatively extend camera distance/far plane for narrow views; invalid or extreme sizes cannot produce nonfinite matrices.

`RendererAssetDescriptor` identifies asset type, role, schema, geometry ID/revision, coordinates, units, origin/scale, source, provenance, license scope, local ownership marker, optional product/variant IDs, material model, renderer capability and personalized status.

The current registry approves only the exact first-party procedural mannequin/garment descriptors, schema 1, `solidColorLambert`, capability **`fitcheck.r0.metal.v1`**, no product/variant association and no personalized status. Changed identities/revisions/schema/coordinates/materials/rights/ownership or unknown/imported/remote/USDZ assets are rejected. Descriptive metadata does not grant rights or authenticate ownership.

A missing or incompatible garment does not turn into a fictional retailer asset or prevent the mannequin from rendering. It reports a distinct error and can restore the explicitly named sample garment without replacing the mannequin or scene. Missing graphics/setup failures show a retryable unavailable screen. GPU command errors are reported to the current presentation owner; disposed/old scene completions cannot interrupt a replacement.

A valid catalog SKU does not authorize a 3D model. A valid saved avatar metadata record does not prove geometry exists. The generic registry is deliberately **not** connected to `AvatarProfileRecord`, and the existing default renderer-compatibility decision for personalized metadata remains unavailable.

## Interaction, navigation and lifecycle

- Drag the native viewport to rotate; four labelled rotation/tilt buttons provide a non-gesture alternative.
- Reset View, show/hide garment, named material choices with checkmark/selected accessibility state, and Reset Appearance affect the existing scene rather than rebuilding it.
- A viewport stays visible while controls scroll. At accessibility sizes, controls use a wide single-column layout and rotation labels avoid space-consuming decorative icons. Text is not globally reduced to make a test pass.
- The initial narrow-column layout produced real word splitting/unreachable control behavior at largest text. Its regression was retained and the layout repaired.
- Entry is **Debug hub → 3D Renderer Lab**. No renderer-only launch flag was introduced. Existing three flags and all conflict/repetition behavior are preserved; normal launch and every Release launch stay legacy home.
- `RootView` retains the sole navigation stack. Lab navigation neither owns nor persists scanner state.
- Repeated `open` calls retain one scene. Dismissal clears the owner; late foreground/retry cannot reopen it. Background/inactive state disposes the scene; foreground creates one replacement with the prior view/appearance. Genuine dismissal/reentry starts a fresh default presentation.
- Disposal clears delegate/callbacks, releases drawables/depth attachments, pipelines, queue and owned GPU buffers. In-flight Metal commands may hold their encoded resources until completion; owner callbacks are weak and identity checked. There are no renderer timers, observers, global mutable scene caches, AR sessions or per-gesture mesh rebuilds.

## Privacy and asset rights

All mesh and shader code was authored for this assignment. No third-party models, licensed retailer photographs, downloaded media, paid services or rendering dependencies were added. Fixture descriptors restrict use to this internal development scope; they are not evidence that a future external asset has commercial rights.

The lab has no camera, ARKit, RealityKit, Vision, scan buffer, saved-profile, catalog-repository, network, analytics or storage dependency. No identifying observations, raw scans or personalized geometry are read, persisted, logged or uploaded by it. Existing legacy app-global preferences remain untouched and unmigrated.

The unchanged built privacy declarations were parsed from Debug simulator, normal Release simulator and Debug iPhone bundles: `SystemBootTime` → `35F9.1`, `UserDefaults` → `CA92.1`, tracking false and collected-data array empty. This is not App Store privacy approval.

## Fresh verification results

| Check | Newly observed result |
| --- | --- |
| XcodeGen generation | Passed |
| Final clean Debug build + full combined suites | **175 passed: 164 unit + 11 UI; 0 failed, 0 skipped** |
| Native Metal cutover targeted suite | **24 passed; 0 failed/skipped**, before the final resize-boundary regression was added |
| Unsigned generic iPhone SDK Debug build | Passed; no physical installation/execution |
| Normal production Release simulator build | Passed; no testability override |
| Final Release route/privacy/isolation suite | **11 passed; 0 failed/skipped** |
| Separate final lifecycle resource-observation run | **1 UI test passed; 0 failed/skipped**, in addition to the full suite, not added to its count |
| Debug/Release binary inspection | All 12 checked renderer/mesh/shader/internal markers present in Debug and absent from normal Release |
| Three built bundle privacy manifests | Both required reasons preserved; declared tracking/collection unchanged |
| Actual simulator interaction/visual review | Generic geometry, side rotation, hide/show, color changes, resets, reentry, foreground recovery and largest text observed |
| Physical renderer GPU/energy/thermal behavior | **NOT RUN** |
| Physical scanner Segment 1B | **NOT RUN — no LiDAR test phone** |

The final Debug run was iPhone 17 Pro simulator, iOS 26.5. Final Release UI isolation used iPhone 17 simulator, iOS 26.5. The 149-test baseline coverage remains included; no meaningful existing assertion was removed, skipped or weakened.

UI rendering proof is not a Boolean-only model assertion. UI tests sample cropped pixels from the actual native viewport, require visible garment pixels, observe spatial pixel changes after dragging/hiding/material selection, and compare reset/reentry images. Sage also requires actual green pixels; hiding requires navy pixels to disappear. Entity/buffer/unit tests are not labelled as screenshot evidence.

Two initial test-helper problems were corrected without weakening the product contract: a parent SwiftUI accessibility identifier overwrote the native viewport identifier; and a whole-image mean color threshold diluted a clearly visible small garment change with its large background. Actual captured imagery measured that difference; the test now checks spatially changed pixels plus the material-specific predicates. Compiler-only issues in new helpers/numeric overloads were also fixed before the final passing clean run.

### Commands and local evidence

From the repository, these commands reproduce the final checks using the paths used in this session (choose unused result paths for another run):

```sh
ARTIFACTS=/Users/anshbalusa/fitcheck-r0-artifacts
DEBUG_SIM=7F050083-C268-4F37-B730-C677F19A88EA
RELEASE_SIM=D5BE86CA-76FC-4C6A-BD88-5D29FFF910F5

xcodegen generate
xcodebuild -project FitCheck.xcodeproj -scheme FitCheck -configuration Debug \
  -destination "platform=iOS Simulator,id=$DEBUG_SIM" \
  -derivedDataPath "$ARTIFACTS/debug" \
  -resultBundlePath "$ARTIFACTS/final-full-debug.xcresult" \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO clean build test -quiet

xcodebuild -project FitCheck.xcodeproj -scheme FitCheck -configuration Debug \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath "$ARTIFACTS/iphone" \
  -resultBundlePath "$ARTIFACTS/metal-iphone.xcresult" \
  CODE_SIGNING_ALLOWED=NO build -quiet

xcodebuild -project FitCheck.xcodeproj -scheme FitCheck -configuration Release \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$ARTIFACTS/release" \
  -resultBundlePath "$ARTIFACTS/metal-release.xcresult" \
  CODE_SIGNING_ALLOWED=NO build -quiet

xcodebuild -project FitCheck.xcodeproj -scheme FitCheck -configuration Release \
  -destination "platform=iOS Simulator,id=$RELEASE_SIM" \
  -derivedDataPath "$ARTIFACTS/release-tests" \
  -resultBundlePath "$ARTIFACTS/final-release-isolation.xcresult" \
  -parallel-testing-enabled NO \
  -only-testing:FitCheckTests/AvatarFeatureIsolationTests \
  -only-testing:FitCheckTests/CatalogIsolationTests \
  -only-testing:FitCheckTests/InternalDevelopmentRouteTests \
  -only-testing:FitCheckTests/IntegrationPrivacyManifestTests \
  -only-testing:FitCheckUITests/AvatarPilotUITests \
  -only-testing:FitCheckUITests/CatalogUITests/testNormalLaunchAndReleaseOptInRemainIsolated \
  -only-testing:FitCheckUITests/IntegrationUITests/testInternalRouteFlagsRemainLegacyInRelease \
  -only-testing:FitCheckUITests/RendererUITests \
  ENABLE_TESTABILITY=YES CODE_SIGNING_ALLOWED=NO test -quiet
```

The testability override applies only to the separate Release test build. The normal production artifact above has no such override.

Results were inspected with `xcresulttool get test-results summary/tests`; screenshots were exported with `xcresulttool export attachments`. Final visual attachments are in `final-ui-proof/`, with earlier Metal cutover images in `metal-ui-proof/`. Evidence is outside Git and contains synthetic/no-person app UI, not scans.

Binary `strings -a` checks covered: `RendererLabView`, `RendererSceneSession`, `RendererProceduralAssets`, `RendererMesh`, `renderer.scene`, `internal.open-renderer`, `fitcheck.r0.metal.v1`, `rendererVertex`, `rendererFragment`, `CatalogRootView`, `AvatarScannerModel`, and `local-synthetic-fixture`. The Debug runtime dylib is the positive control; the normal Release executable is the negative control. Parsed results are in `final-binary-privacy-verification.json`.

## Lifecycle and performance observations

The separate `profiled-lifecycle.xcresult` run exercised four actual exit/reentry cycles, rotation/reset comparison, home/foreground recovery, then scanner unsupported/cancel and catalog navigation. It passed. Real native GPU buffers and weak session/view ownership also release in deterministic repeated-cycle tests; old completion callbacks cannot revive or replace a scene.

A finite host `footprint -p` sampler, with contemporaneous synthetic simulator screenshots, recorded the same process through that run. Values below are rounded MB as reported by `footprint`, not FPS or a hardware budget:

| Observed phase | Process footprint |
| --- | --- |
| First visible lab | 45 MB |
| Reopened lab after repeated navigation | 49 MB |
| Foreground/recreated lab | 50 MB |
| Final hub after scanner/catalog paths | 52 MB |

Peak observed footprint was 53 MB. Data and matching screenshots are in `memory-observations.json` and `memory-*.txt/png`. This short run shows modest warm-up growth, not proof of a leak-free long-running app or a plateau under unlimited repetition. No duplicate visible scene, crash, transform drift or retained app-owned session was observed in the passing Metal runs. No mesh/index buffer is rebuilt for a rotation, visibility or color update.

Instruments was attempted rather than assumed available: simulator Activity Monitor reported **“Activity monitoring service not available on this device”**; Time Profiler attach reported **“Cannot find process for provided pid”** despite the separate host footprint sampler observing the simulator process. Consequently there is **no successful Instruments timing/allocation trace**, measured FPS, frame-latency bound, power result or thermal result to claim. The earlier native `sample` captures diagnosed the removed RealityKit backend, not MetalKit performance. Physical GPU profiling and a longer steady-state memory soak remain unverified.

Xcode's existing destination/debugger diagnostics, generic-iPhone orientation warning, and weak-reference-test compiler suggestions were not suppressed. No product quality gate or old regression was disabled to obtain green results.

## Future integration requirements and explicit limits

1. Keep generic fixture identity separate from an approved personalized geometry identity. Scanner observation pairs and profile structure are not geometry approval.
2. A real local asset importer must be separately authorized and implemented, with bounded validated vertex/index data, units, coordinate conversion, bounds, origin/pivot, material mapping, version/revision, privacy/owner checks and error recovery. A declared `.usdz` type is currently rejected, not loaded.
3. Add a reviewed USDZ/Model I/O or other approved conversion path only against concrete assets. Do not pretend this minimal renderer already supports arbitrary USDZ scenes, skeletons, animations, textures or materials.
4. Garment model identity/revision, real retailer/product/variant association and media/model/derivative commercial licensing must be independently reviewed. Catalog validity alone does not authorize one.
5. Local ownership markers are descriptive, not account isolation or an authorization system. Existing device-scoped storage and account/concurrent-writer gaps remain unchanged.
6. Validate renderer performance, lifecycle and accessibility on actual supported iPhones and oldest supported iOS. Manual VoiceOver speech/rotor, energy/thermal behavior, extended resource soak and physical GPU behavior are **NOT RUN**.
7. Segment 1B remains blocked. R0 adds no new scanning behavior, personal reconstruction, manual body input, fitted garment simulation, fit percentages/size recommendations, live retailer service, accounts, checkout, Android or commercial-release approval.

**Final verdict: GO for review of Segment R0 as an isolated, genuinely interactive native generic rendering foundation. No authorization to merge, begin Segment 1B, create personalized geometry, or start another segment follows from this verdict.**
