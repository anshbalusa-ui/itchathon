# Segment I0 — integrated development application

## Inputs and dependency chain

The local tree was clean before work. Fetched `origin` and inspected the current source, PR descriptions and open/draft state before integration. Starting heads:

| Ref | Exact commit | Target |
| --- | --- | --- |
| `main` | `562173fa592330c19c04d29db2850be6018db0f4` | — |
| PR #8 / `feature/avatar-s0-hardening-20261019` | `aa3e980bcd8c65f823c1ded1ba474c9dd14ece14` | `main` |
| PR #9 / `feature/scanner-s1a-hardening-20261020` | `ae40f06e4e9449a4d0a5dfbef19ad280f67dd35a` | PR #8 branch |
| PR #10 / `fix/foundation-audit-20261020` | `55a0c1cb3319363c84f13944c0bdaa6717d5c564` | PR #9 branch |
| PR #11 / `feature/catalog-foundation-20261020` | `e0f7b64af82e42f240818b6aa2e4f1823adcbba1` | `main` |

Created `integration/avatar-scanner-catalog-20261020` directly from the fetched PR #10 head. Cherry-picked the single reviewed PR #11 commit; conflict-resolved commit is `f346176`. No unrelated history, PR #5 code, merge to main, or modification of the independent PR branches. The integration PR targets **`fix/foundation-audit-20261020`**: I0 → #10 → #9 → #8 → main; #11 remains an independent input, not an additional scanner dependency.

## Conflicts and deliberate resolutions

- `RootView.swift`: both branches used the avatar flag for different modules. Retained the repaired avatar entry during the cherry-pick, then replaced the old single-feature gate with `InternalDevelopmentRoute`. There are no deprecated aliases silently redirecting the avatar flag to catalog.
- `PrivacyInfo.xcprivacy`: retained PR #10's complete manifest, not the shorter catalog copy. Actual combined source uses `ProcessInfo.processInfo.systemUptime` in `AvatarScannerModel` and app-local `UserDefaults` in the legacy `ProfileStore`: `SystemBootTime` / `35F9.1` and `UserDefaults` / `CA92.1` both remain. No tracking or off-device collection is declared. This is not App Store privacy approval.
- `README.md`: retained foundation/scanner audit links and integrated current catalog launch instructions. Historical independent build/test records remain historical, not new scanner validation.
- Avatar onboarding had stale statements that the build had no catalog. Updated only that copy: catalog browsing exists independently and is not avatar/body/fit evidence.

## Debug routing contract

| Launch argument | Entry |
| --- | --- |
| None / no recognized internal flag | Existing legacy `HomeView` |
| `-fitcheck-avatar-internal` | Existing avatar metadata onboarding / scanner entry |
| `-fitcheck-catalog-internal` | Independent synthetic offline catalog |
| `-fitcheck-integrated-internal` | Clearly marked internal hub with links to both modules |
| Conflicting distinct internal flags | Legacy home, fail closed |
| Repeated identical flag | Same requested route; not a conflict |
| Any arguments in Release | Legacy home only |

Arguments match exactly; prefixes, missing hyphens and `=true` are not aliases. The resolver is deterministic and has no persistence or sensor side effects. `RootView` owns the only navigation stack. The hub only composes destinations; it does not own camera buffers, selections, avatar readiness or a second navigation container. The scanner retains its existing full-screen presentation and cancellation/dismantle boundaries. No body information is needed to browse.

## Ownership and protected behavior

- Scanner: existing main-actor camera/model owner, identity-checked callbacks/dismantling, generation-tagged analysis, one physical analysis worker, attempt-local front/pair and discard on cancellation/background/exit. Source capture algorithms and thresholds from PR #10 are preserved. A provisional pair is never saved to the profile repository or promoted to geometry.
- Profiles: existing schema-first validation and typed missing/incomplete/invalid/unsupported/I/O handling, complete-protection sibling staging, atomic rename, backup exclusion and file-only deletion including the cached-file-kind repair. Legacy preferences are not migrated or deleted. Default renderer support remains absent.
- Catalog: existing actor-owned validated snapshot, scoped product/SKU identity, explicit availability/price/measurement source and units, selection generations and independent detail models. It has no scan/profile repository dependency, raw-buffer parameter, disk sink or network client. Fixtures are fictional, photographs are absent and SF Symbol placeholders remain labelled.
- Hub: native navigation only. Popped detail/scanner views do not become global state or a shared session. No fake avatar or fit readiness is introduced.

## Future service and account boundaries

Sensitive scan/evidence stays on-device. Profiles remain independent of catalog lookup; catalog provenance and option selection are not geometry/fit evidence. A future authorized adapter may own retailer credentials, normalized product/SKU identity and authoritative price/stock/media entitlement. UI consumes the existing repository contract, not transport payloads. Plain scalar models, schema versions and explicit units can inform a future Android contract without claiming sensor parity.

There is **no account isolation**: protected avatar data and legacy preferences are app/device scoped. Repository actors serialize per instance, not across independently created actors/processes; the reserved pending filename is shared within a directory. Before accounts, sync, concurrent writers or multi-scene write paths, define one coordinated owner or reviewed filesystem coordination, owner-scoped migration, sign-out/deletion and conflict policy. Do not silently attach an anonymous device profile to the next account. No speculative account/network infrastructure was added in I0.

## Unverified physical requirements — NOT RUN

The LiDAR iPhone is unavailable. No device discovery/capture, permission or real-device validation was attempted. [Segment 1B checklist](SCANNER_S1B_DEVICE_CHECKLIST.md) and [foundation audit](FOUNDATION_AUDIT.md) remain authoritative. In particular: actual RGB/Vision/depth registration, ordinary left/right side occlusion, missed-person/handoff rejection, real permission/interruption/session cleanup, app-switcher privacy, retained buffers/memory/thermal/latency, hardware file protection/backup and oldest-supported-device behavior remain **NOT RUN**.

Simulator unsupported-camera cancellation and deterministic synthetic lifecycle tests cannot establish those physical results. I0 does not authorize avatar geometry, garment simulation, try-on, fit prediction or customer release. The legacy manual/score flow is preserved for compatibility, not approved as the final retailer journey.

## Integration regression and quality review

- Migrated the existing avatar/catalog opt-in assertions to the shared resolver without weakening their isolation contract. Avatar's flag retains its established meaning; catalog now has its own explicit flag.
- Added deterministic route checks for exact arguments, repeated identical flags, every distinct conflicting pair/order and all three flags.
- Added actual-bundle privacy checks for both required-reason declarations and no declared tracking/collection.
- Added real temporary-filesystem/repository integration coverage: catalog loading/selection/source failures preserve protected profile bytes and meaning; profile deletion leaves catalog lookups/selection intact; missing, pending, unsupported and corrupt profiles never gain readiness from browsing.
- Retained PR #10's lifecycle, continuity, false-front, deletion-safety, schema/protection/recovery and no-renderer tests, plus PR #11's scoped-product/foreign-SKU and stale-selection regressions.
- Added actual simulator hub → avatar → scanner unsupported/cancel → hub → catalog → two different products → hub → scanner reopen coverage. A largest-accessibility-text scenario exercises both modules and scanner cancellation.

The first integration smoke executed **10 tests: 8 passed, 2 failed, zero skipped** (`/tmp/fitcheck-i0-navigation-smoke.xcresult`). The normal-navigation failure was an overly narrow new test query (`Other` versus the actual scroll-view accessibility element); the navigation paths themselves completed. The selector now uses the specified identifier across element types.

The large-text failure exposed a **real recovery defect**: the scanner's vertically fixed instruction card exceeded the available viewport and pushed cancellation above the screen. Captured UI hierarchy placed the Cancel button at negative Y, and its hittability assertion failed. Replaced the unbounded fixed layout with `ViewThatFits`: retain the compact card when it fits, otherwise use a viewport-bounded scrolling card. Cancellation stays outside that scroll area, with an explicit accessible label/identifier and an icon-only visual control to avoid text truncation. No capture algorithm, threshold or session ownership changed.

A temporary injected offline repository and UI smoke exercised actual empty, source-unavailable and malformed-feed screens, including retry and no fabricated products. All three surfaces were visually reviewed; the smoke passed. Temporary injection/source/test files were removed and normal catalog composition restored before final verification. Proof contains only no-person simulator UI and synthetic catalog data, outside Git at `/tmp/fitcheck-i0-smoke-proof/`.

The next targeted run confirmed normal integrated navigation and visible, tappable large-text cancellation. Its remaining assertion failure was a new test helper demanding that offscreen lazy-grid controls exist before scrolling. The helper now performs bounded scrolling first, then still asserts existence, hittability and actual selection. Visual review also found fixed-width catalog color names splitting short words and a scaled checkmark overflowing its fixed swatch. Color and size option widths now scale with text; decorative swatch glyphs stay within the fixed swatch. Large-text coverage now actually changes color and selects an available size, not merely queries controls.

## Verification environment and commands

Xcode 26.5 (`17F42`), XcodeGen 2.46.0. Selected an available iPhone dynamically from `xcrun simctl list devices available -j`, preferring a booted iPhone and newer available iOS runtime; did not assume the historical UUID remained valid. Actual selection: iPhone 17 Pro simulator / iOS 26.5 (`23F77`), `7F050083-C268-4F37-B730-C677F19A88EA`.

Final application/test commands actually executed from the repository:

```sh
xcodegen generate
plutil -lint Sources/Support/PrivacyInfo.xcprivacy

xcodebuild -project FitCheck.xcodeproj -scheme FitCheck -configuration Debug \
  -destination 'platform=iOS Simulator,id=7F050083-C268-4F37-B730-C677F19A88EA' \
  -derivedDataPath /tmp/fitcheck-i0-derived \
  -resultBundlePath /tmp/fitcheck-i0-full-debug.xcresult \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO clean build test -quiet

xcodebuild -project FitCheck.xcodeproj -scheme FitCheck -configuration Debug \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/fitcheck-i0-iphone \
  -resultBundlePath /tmp/fitcheck-i0-iphone-build.xcresult \
  CODE_SIGNING_ALLOWED=NO build -quiet

xcodebuild -project FitCheck.xcodeproj -scheme FitCheck -configuration Release \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/fitcheck-i0-release \
  -resultBundlePath /tmp/fitcheck-i0-release-build.xcresult \
  CODE_SIGNING_ALLOWED=NO build -quiet

xcodebuild -project FitCheck.xcodeproj -scheme FitCheck -configuration Release \
  -destination 'platform=iOS Simulator,id=7F050083-C268-4F37-B730-C677F19A88EA' \
  -derivedDataPath /tmp/fitcheck-i0-release-tests \
  -resultBundlePath /tmp/fitcheck-i0-release-isolation.xcresult \
  -parallel-testing-enabled NO \
  -only-testing:FitCheckTests/AvatarFeatureIsolationTests \
  -only-testing:FitCheckTests/CatalogIsolationTests \
  -only-testing:FitCheckTests/InternalDevelopmentRouteTests \
  -only-testing:FitCheckTests/IntegrationPrivacyManifestTests \
  -only-testing:FitCheckUITests/AvatarPilotUITests \
  -only-testing:FitCheckUITests/CatalogUITests/testNormalLaunchAndReleaseOptInRemainIsolated \
  -only-testing:FitCheckUITests/IntegrationUITests/testInternalRouteFlagsRemainLegacyInRelease \
  ENABLE_TESTABILITY=YES CODE_SIGNING_ALLOWED=NO test -quiet
```

`ENABLE_TESTABILITY=YES` is command-only on the separate Release verification build; normal production settings/project configuration were not weakened. The iPhone SDK command is unsigned compilation, not installation or device execution.

Built-manifest `plutil -lint` succeeded for Debug simulator, Release simulator and Debug iPhone SDK app bundles. Parsed all three actual bundle declarations: `SystemBootTime: [35F9.1]`, `UserDefaults: [CA92.1]`, tracking false, collected-data array empty. The manifest is unchanged relative to PR #10.

`strings -a` inspection found all of these in the actual Debug runtime dylib and none in the normal Release executable: `AvatarPilotRootView`, `AvatarScannerModel`, `AvatarGuidedCaptureController`, `PersonDepthAligner`, `CatalogRootView`, `OfflineCatalogRepository`, `InternalDevelopmentHub`, `start-guided-scan`, `internal.open-catalog`, `sample-studio`, `local-synthetic-fixture`. This checks new unfinished surfaces, not removal of the preserved legacy camera tools.

Reviewed actual final simulator captures at `/tmp/fitcheck-i0-final-ui-proof/`: honest metadata onboarding, compact scanner recovery, largest-text bounded recovery with visible cancellation, catalog color/size selection and scanner reentry. Combined UI tests exercised native navigation, accessible names/selected/disabled states, cancellation and unrelated-product selection isolation. Manual VoiceOver rotor/speech, additional devices/oldest iOS and real camera/memory behavior remain unverified. The existing generic-iPhone orientation/full-screen warning and simulator debugger-version messages were not suppressed.

## Final observed results and decision

| Check | Actual result |
| --- | --- |
| XcodeGen + source manifest validation | Passed |
| Clean full Debug build and combined suites | **149 passed: 141 unit + 8 UI; 0 failed, 0 skipped** |
| Unsigned generic-iPhone Debug build | Passed; no device execution |
| Normal production Release simulator build | Passed; no testability override |
| Release routing/privacy unit tests and actual launch isolation UI tests | **9 passed; 0 failed, 0 skipped** |
| Debug/Release/iPhone bundle manifest inspection | Both required reasons retained; no tracking/collection declared |
| Normal Release binary isolation | All eleven new pilot/scanner/catalog/hub/fixture markers absent; present in Debug positive control |
| Actual simulator UI quality | Reviewed normal and largest-text paths, truthful missing avatar/measurement states, independent selection, unsupported cancel/reopen, empty/unavailable/error/retry |
| Physical Segment 1B | **NOT RUN — hardware unavailable; no claim of validation** |

The final combined count comes from the executed result bundle, not adding the independent PR totals. All relevant existing suites were retained. Final proof includes the meaningful large-text cancellation regression and color/size interaction after layout repair, not the removed temporary state-smoke fixture.

**GO for Segment I0 as an integrated internal development application, pending review.** Not GO for physical scanner validity, personalized geometry, virtual try-on, fit prediction or retailer customer release. There are no known failing I0 checks in the final runs. Review the draft integration PR against PR #10; do not merge any dependency automatically.

## Exact integration delta relative to PR #10

| File | Purpose |
| --- | --- |
| `Docs/CATALOG_FOUNDATION.md` | Bring PR #11 record; mark original routing/manifest statements historical |
| `Docs/RETAILER_CATALOG_CONTRACT.md` | Preserve minimum authorized retailer/media/data boundary |
| `Docs/INTEGRATION_HANDOFF.md` | Starting heads, strategy, conflicts, actual proof and unresolved risks |
| `README.md` | Current three-route launch contract and legacy distinction |
| `Sources/AvatarNext/AvatarExperienceFeatures.swift` (removed) | Retire conflicting single-feature entry gate; all code consumers migrated |
| `Sources/AvatarNext/AvatarPilotRootView.swift` | Remove stale no-catalog claims without fabricating readiness |
| `Sources/Catalog/CatalogModels.swift` | PR #11 validated portable domain, unchanged |
| `Sources/Catalog/CatalogRepository.swift` | PR #11 replaceable repository outcomes, unchanged |
| `Sources/Catalog/CatalogViewModels.swift` | Preserve identity/selection-generation repairs unchanged |
| `Sources/Catalog/CatalogViews.swift` | PR #11 screens plus confirmed large-text control sizing/glyph repair |
| `Sources/Catalog/OfflineCatalogRepository.swift` | PR #11 actor-owned offline implementation, unchanged |
| `Sources/Catalog/SyntheticCatalog.swift` | PR #11 fictional samples, unchanged |
| `Sources/Development/InternalDevelopmentHub.swift` | Small Debug-only composition with native links |
| `Sources/Development/InternalDevelopmentRoute.swift` | Exact deterministic route selection; Release/conflict fail closed |
| `Sources/Scanning/AvatarGuidedCaptureView.swift` | Repair observed large-text overflow/cancellation; preserve capture lifecycle |
| `Sources/Views/RootView.swift` | One navigation owner and deliberate module entry |
| `Tests/AvatarPilotModelTests.swift` | Preserve avatar opt-in isolation against the shared resolver |
| `Tests/CatalogIsolationTests.swift` | Catalog-specific flag and Release rejection |
| `Tests/CatalogModelTests.swift` | Retain PR #11 domain regression coverage |
| `Tests/CatalogPresentationTests.swift` | Retain PR #11 identity/stale-selection/state regressions |
| `Tests/CatalogRepositoryTests.swift` | Retain PR #11 source/repository/error coverage |
| `Tests/IntegrationBoundaryTests.swift` | Actual protected-storage/catalog independence and no readiness promotion |
| `Tests/IntegrationPrivacyManifestTests.swift` | Actual app-bundle required-reason/no-collection contract |
| `Tests/InternalDevelopmentRouteTests.swift` | Integrated/exact/conflicting/repeated argument behavior |
| `UITests/CatalogUITests.swift` | Retain complete catalog UI coverage using its distinct flag |
| `UITests/IntegrationUITests.swift` | Hub return/reopen, unrelated-product isolation, large text and all-route Release rejection |

`Sources/Support/PrivacyInfo.xcprivacy`, `project.yml`, profile persistence/validation, capture coordinator, analyzer, aligner and scanner model remain unchanged from the repaired PR #10 base. No legacy preference migration, external dependency, backend, raw scan storage or next development segment was introduced.
