# Segment R1 — synthetic catalog-to-3D illustrative preview

## Source and integration strategy

- Repository: `anshbalusa-ui/itchathon`; workspace `/Users/anshbalusa/fitcheck-recovery-20261020`.
- Source/PR base: `feature/3d-renderer-foundation-r0`, PR #13, commit `6b30b81944966c68baca209abc32ecac0dac3666`. Local and fetched remote matched; the initial worktree was clean and no integration operation was interrupted. PR #13 was rechecked before delivery and remains an open draft at that commit.
- R1 branch: `feature/catalog-3d-preview-r1`; target the R0 branch, not `main` or PR #11. No merge, cherry-pick, reset, force push, or duplicate catalog integration was needed.
- Dependency chain: R1 → #13 → #12 → #10 → #9 → #8 → main. PR #12's integrated base is `1afe034d7376f16e6c7e993f95931ace45a0d692`.
- R0's **175 Debug / 11 Release isolation tests** are historical starting evidence, not substituted for this segment's runs. See [R0](RENDERER_R0_HANDOFF.md), [I0](INTEGRATION_HANDOFF.md), [catalog](CATALOG_FOUNDATION.md), [retailer contract](RETAILER_CATALOG_CONTRACT.md), [data boundaries](DATA_ARCHITECTURE_AUDIT.md), and [foundation repairs](FOUNDATION_AUDIT.md).

## Explicit association contract

`CatalogPreviewAssociation` is a small Debug-only composition boundary. It accepts the currently loaded product, checked selected variant, selected color ID and selected size ID. It never fetches catalog data, reads a profile, initializes capture, or manages GPU buffers.

Resolution fails closed unless all of these hold:

1. The garment descriptor passes the **unchanged** R0 `.validate(for: .garment)` contract: procedural `fitcheck.illustrative-garment`, schema/revision 1, compatible coordinates/units/scale, bundled first-party provenance, local ownership, internal-development-only license, solid-color Lambert material, capability `fitcheck.r0.metal.v1`, no personalization, and **nil product/variant associations**. A missing fixture, another role/revision/capability/material/license, remote asset or USDZ is not accepted.
2. The product validates as catalog data, is a T-shirt, and has an exact retailer-scoped identity in the four-row association registry.
3. Product provenance is exactly `.synthetic`, revision `sample-v1`, reference `local-synthetic-fixture`. This descriptive metadata is not authentication or a grant of real retailer rights.
4. The selected color belongs to that product and has its reviewed option ID, name and hex value. Unknown or changed mappings are unsupported, not substituted.
5. The selected size is a current option; the listed color/size combination and the selected response both report `.available`.
6. The current listed SKU, selected response SKU/options and explicit reviewed registry row agree. Matching titles, size labels, colors or option combinations cannot authorize a foreign SKU.

Missing prices do not change geometry authorization. The association neither invents a price nor requires the response price to equal an older product-list price. Prices and finished measurements remain catalog concerns and are not renderer inputs.

Successful resolution produces an immutable `CatalogIllustrativePreview`, with file-scoped construction, exact product/SKU/color/size context and the explicitly mapped material. Its identity includes the scoped selection and presentation snapshot. It supplies scalar `RendererPresentation` settings, **not** a retailer-associated `RendererAssetDescriptor`. The procedural asset remains the same unassociated internal fixture.

## Eligible samples and deliberate exclusions

All identities below use the existing `SyntheticCatalog`; no catalog or alternate fixture identities were duplicated.

| Product in fictional `sample-studio` | Reviewed SKUs | Illustration |
| --- | --- | --- |
| `everyday-tee` — Everyday Tee | `everyday-navy-small`, `everyday-navy-medium` | Navy; S/M labels only |
| `weekend-tee` — Weekend Tee | `weekend-sage-small`, `weekend-sage-medium` | Sage; S/M labels only; missing price remains missing |

Policy is **available-only**. Both the current product snapshot and checked variant response must be available; visualization never reserves inventory or makes a sample purchasable.

- Everyday Navy L is out of stock and unassociated.
- **Every Cream variant is unsupported**, including available Cream M. There is no Cream shader mapping in R1; Stone is not a substitute. Cream S is out of stock and Cream L has unknown availability; those ordinary selection states remain intact.
- `archived-tee` / `archive-graphite-medium` is discontinued, unassociated, and cannot open a preview. No Graphite substitute is invented.
- Unknown availability, discontinued/out-of-stock responses, missing/foreign SKUs, unrelated retailers/products, changed provenance, and missing/incompatible fixtures do not open a fallback scene under a product title.
- Size labels never change mannequin or shirt geometry, scale, clearance or measurements. The same R0 factory is used for every eligible SKU. Scene-backed tests compare all garment vertex positions, normals and indices across S/M.

### Material mapping

| Option ID / catalog swatch | Existing renderer material | Linear RGB supplied to the garment shader |
| --- | --- | --- |
| `navy` / `#24364B` | Navy | `(0.12, 0.22, 0.42)` |
| `sage` / `#899786` | Sage | `(0.25, 0.40, 0.32)` |

Alpha remains 1. These are explicitly reviewed **illustrative named colors**, shaded by R0's existing lighting; they are not color-calibrated retailer/fabric reproductions. Stone remains available only in the independent Renderer Lab. No new material, image, model, texture or third-party dependency was added.

## Navigation, ownership and interactions

- `CatalogDetailViewModel` derives eligibility from its actual loaded product and checked selection. `openPreview()` resolves again rather than trusting an old enabled button. It owns one published presentation snapshot.
- Color changes, size checks and product reloads clear the presentation synchronously. Existing product/variant request generations and exact expected-SKU checks remain intact. A late response cannot overwrite a newer selection or its preview.
- `CatalogDetailView` uses `navigationDestination(item:)` within the existing navigation owner. Popping clears only the presentation, preserving selected size/color. Different product detail models have separate immutable product identities; reopening creates the current selection's viewer rather than a shared global preview.
- The action is **View illustrative 3D preview**. It is disabled with an explicit explanation when unsupported or awaiting a checked variant. Both details and viewer disclose generic, geometric, non-scan-derived, non-sized/non-draped/non-fit status. The personalized-avatar-unavailable notice now distinguishes personalized capabilities from this generic illustration.
- `RendererPresentation` contains only title/context, initial material and whether material changes are allowed. The renderer core does not import catalog types or fetch from `CatalogRepository`.
- Product previews show product/color/size-label context, use the chosen supported material and lock it against unrelated color changes. Return to details to change the selection. The independent Renderer Lab still offers Navy/Stone/Sage.
- Drag rotation, accessible rotation/tilt buttons, Reset View, garment visibility and Reset Appearance reuse R0. Appearance reset restores the **selection's initial material and visible garment**, not unconditional Navy; it does not reset rotation. View reset does not change appearance.
- R0's MetalKit/Metal engine, meshes, coordinate conventions, camera, shader, buffers, failure handling and disposal are unchanged. Coordinates remain right-handed, +Y up, +Z forward, metre units, floor-root origin and fixture scale 1. None of these stylized proportions are body or garment measurements.
- One `RendererLabModel` owns one `RendererSceneSession`. Dismissal disposes it; backgrounding releases scene resources, foregrounding recreates the scene with current appearance/orbit; weak, identity-scoped callbacks reject obsolete GPU failures. Source catalog state owns no Metal objects.
- At accessibility text sizes, four constant rotation controls are eager rather than virtualized; the garment switch sits below its wrapping label. The scene and back control stay visible while instructions/controls scroll. Tests retain real hit-target assertions and use short, bounded, held drags rather than inertial flicks that can skip an entire oversized button.
- No launch route was added. Default Debug launch remains legacy; existing avatar/catalog flags retain their independent entries; the integrated flag still opens the hub with all three modules. Conflicts fail closed, and Release ignores internal flags.

## Changed files and responsibilities

| Files | Responsibility |
| --- | --- |
| `Sources/Catalog/CatalogPreviewAssociation.swift` | Explicit association registry, denial reasons, immutable preview snapshot and renderer composition |
| `Sources/Catalog/CatalogViewModels.swift` | Current-selection eligibility, presentation ownership and synchronous invalidation |
| `Sources/Catalog/CatalogViews.swift` | Accessible action, unsupported explanation, existing-stack navigation and truthful personalized-avatar distinction |
| `Sources/Rendering/RendererContracts.swift` | Scalar presentation settings; initial-material appearance reset; asset validation unchanged |
| `Sources/Rendering/RendererLabModel.swift` | Selected initial appearance, color lock and reset baseline; existing scene ownership retained |
| `Sources/Rendering/RendererLabView.swift` | Product context, independent lab controls, accessible layout and garment switch |
| `Tests/CatalogPreviewAssociationTests.swift` | Scoped identity, SKU/options/provenance, availability, unsupported color and asset compatibility boundaries |
| `Tests/CatalogPreviewPresentationTests.swift` | Actual selection/reopen, no size-specific mesh, stale async responses, retry/reload and changed availability |
| `Tests/RendererPresentationTests.swift` | Native scene color/visibility/reset, material lock, background/retry and disposal |
| `Tests/IntegrationBoundaryTests.swift` | Real preview operations preserve protected profile bytes and missing/pending/unsupported/corrupt readiness semantics |
| `UITests/RendererUITests.swift` | Two catalog-to-GPU workflows, real pixels, repeated navigation, accessibility and added Release absence assertions |
| `README.md`, this handoff | Entry instructions, boundaries and evidence |

## Licensing, privacy and future assets

The existing mannequin and shirt are first-party procedural geometry, with no downloaded or third-party assets. This association permits only an internal fictional illustration. It does not assert that the shirt is a real sample product model, licensed retailer media, accurate physical construction or a fit result.

The new flow uses no personal profile, raw image, depth, mask, landmark, measurement, account, network, analytics or persistence input. Unit integration scenarios actually open/operate/close a scene while verifying protected bytes and profile routing are unchanged. UI scenarios show no camera permission alert; source dependencies, not that assertion alone, establish that this path does not initialize capture. Physical camera/privacy behavior remains outside this simulator evidence.

The source manifest and Debug/Release/iPhone bundle declarations remain complete: System Boot Time `35F9.1`, app-owned UserDefaults `CA92.1`, tracking false and collected-data array empty. No manifest change was made. This is not App Store privacy approval.

A real garment path still requires separately authorized retailer/product/SKU association, geometry/media/derivative rights, explicit revisions, validated units/origin/scale and bounds, compatible materials/color mapping and reviewed provenance. R0's rejection of real/remote/USDZ descriptors remains. A bounded audited importer/converter and concrete licensed assets would be a separate assignment; R1 adds no importer, downloader or speculative service. Personalized geometry additionally requires approved scan-derived evidence, actual geometry identity/ownership and a compatible renderer; neither a valid metadata record nor this fixture association supplies those prerequisites.

## Fresh verification — 2026-10-21

Environment: Xcode 26.5 (`17F42`), XcodeGen 2.46.0, iOS 26.5 (`23F77`) x86_64 simulators. Debug uses iPhone 17 Pro `7F050083-C268-4F37-B730-C677F19A88EA`; Release isolation uses iPhone 17 `D5BE86CA-76FC-4C6A-BD88-5D29FFF910F5`, both verified available rather than assumed from old records. Unsigned iPhone compilation uses the installed generic device SDK.

| Check | Fresh result / evidence under `/Users/anshbalusa/fitcheck-r1-artifacts` |
| --- | --- |
| XcodeGen generation | Passed |
| Final clean Debug build plus complete unit/UI suite | **194 passed: 181 unit + 13 UI**, zero failures/skips; `debug-full-final.xcresult` |
| Largest-text catalog-to-GPU correction scenario | 1 passed, zero failures/skips; `large-text-final.xcresult` |
| Unsigned generic-iPhone Debug SDK build | Passed; `iphone-verified-final.xcresult` |
| Normal production Release simulator build | Passed, no testability override; `release-verified-final.xcresult` |
| Final-source Release route/privacy/isolation suite | 11 passed, zero failures/skips; `release-verified-isolation.xcresult` |
| Binary isolation | 17 expected development markers present in Debug, all absent from normal Release; `final-binary-privacy-verification.json` |
| Privacy manifests | Complete unchanged declarations verified in all three bundles |

The final complete run preserves the 175-test R0 coverage and adds 19 R1 tests: seven association, seven catalog-selection/lifecycle, three renderer-presentation and two simulator UI tests. Native scene-object tests are not presented as pixel proof; the UI tests exercise real rendered geometry and materials.

The first attempt found missing `try` in a new throwing fixture helper and was corrected before tests could run. The initial complete Debug execution ran 194 tests: 192 passed and two failed (one new rejection-category assertion, one new largest-text scenario). The category now consistently rejects unknown colors as unsupported. The largest-text scenario exposed lazy control discovery, inertial test scrolling that oscillated past controls, and a wrapped toggle's unreliable target. Eager controls, bounded test gestures and a separately placed accessible switch corrected these issues. No old assertion, pixel threshold or quality gate was removed, skipped or relaxed.

### Reproduction commands

```sh
ARTIFACTS=/Users/anshbalusa/fitcheck-r1-artifacts
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
  -resultBundlePath "$ARTIFACTS/iphone-verified-final.xcresult" \
  CODE_SIGNING_ALLOWED=NO build -quiet

xcodebuild -project FitCheck.xcodeproj -scheme FitCheck -configuration Release \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$ARTIFACTS/ReleaseDerived" \
  -resultBundlePath "$ARTIFACTS/release-verified-final.xcresult" \
  CODE_SIGNING_ALLOWED=NO build -quiet

xcodebuild -project FitCheck.xcodeproj -scheme FitCheck -configuration Release \
  -destination "platform=iOS Simulator,id=$RELEASE_SIM" \
  -derivedDataPath "$ARTIFACTS/ReleaseTestDerived" \
  -resultBundlePath "$ARTIFACTS/release-verified-isolation.xcresult" \
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

Run from the repository; result bundle paths above are completed-evidence locations and must be changed for another execution. The testability override applies only to the separate Release test build, never the normal production artifact.

`xcresulttool get test-results summary/tests` provides counts and outcomes; `xcresulttool export attachments` exports actual app captures. Binary checks use `strings -a` on Debug's `FitCheck.debug.dylib` as positive control and the normal Release executable as negative control. Markers include the three new preview/presentation types, preview action/context IDs and text, Renderer Lab/session/procedural types, renderer scene/hub IDs, renderer capability/shader entries, catalog root, scanner model and synthetic provenance reference. Parsed bundle manifests verify both exact reason codes plus false/empty tracking/collection.

### Actual simulator and resource observations

Real screenshot pixels, not just scene labels or model Booleans, distinguish Navy and Sage, show the garment disappearing while the mannequin remains, change under drag/buttons, and return to the reference image after resets/reentry. Tests visit the integrated hub, actual product/color/size controls, preview, source details, another product, discontinued Archive, independent Lab and scanner unsupported/cancel navigation. The standard-size scenario repeats entry/exit four times, backgrounds/foregrounds the actual app, preserves selection, and restores Sage rather than Navy after Reset Appearance. Largest accessibility XXXL repeats the product flow, rotation/visibility/reset, Cream rejection, independent Sage context and return to the hub.

Inspected synthetic-only captures are retained outside Git in `final-ui-proof/`, exported from the complete passing final-source run, and `large-text-proof/`, from the passing focused accessibility correction run. Earlier targeted captures remain in `targeted-visuals/` as diagnostic history. No personal body/scan image or test artifact was committed.

Coarse native `footprint -p` observations and matching simulator screenshots are in `r1-profile-observations.json` and `r1-profile-*.txt/png`. In the targeted normal-size R1 run, the same app process (PID 14218) was observed from the selected Navy detail through repeated preview/navigation/background, independent Sage and return to other modules. Its post-warm-up observations ranged **48–56 MB**, with a reported process peak of **56 MB**. This profiling run preceded the final accessibility-only switch placement/test-gesture correction; the normal-size renderer and Metal backend were unchanged. Larger-text observations are separate process launches, not cumulative leak growth.

No crash, duplicate visible scene or transform-reset drift was observed in the passing standard workflow. Native scene tests exercise real GPU-object disposal and weak ownership rather than assuming disappearance frees resources. Short coarse samples do not establish a long-run plateau, leak freedom, a device memory budget, or absence of every stutter. There is no new Instruments trace, measured FPS/frame latency, physical GPU, energy or thermal result. R0's documented simulator Instruments limitations remain historical, not a successful R1 profiling claim.

Xcode's existing destination/debugger diagnostics and weak-reference-test compiler suggestions were not suppressed. No meaningful baseline test was removed or weakened.

## Limits and verdict

- Cream/Graphite, real or unrelated products and nonavailable variants have no approved preview. No arbitrary material or SKU fallback exists.
- The mannequin, block-like shirt, hard materials and lighting are illustrations, not personal anatomy, verified garment construction, drape, color accuracy, sizing or fit.
- No real asset loading, retailer integration, accounts, backend, checkout, cloud synchronization or Android work was added.
- Physical GPU/accessibility, oldest-supported iOS, manual VoiceOver speech/rotor, long resource soak and physical camera/privacy remain **NOT RUN**.
- Segment 1B physical LiDAR validation is still blocked by the unavailable test phone. Personalized scan-derived geometry and garment fit are **NO-GO**.

**GO for review of Segment R1 as an internal, synthetic catalog-to-3D illustrative preview. NO-GO for commercial release, real retailer asset authorization, personalized geometry, physical sizing/drape or fit. No PR is merged and no subsequent segment is authorized by this verdict.**
