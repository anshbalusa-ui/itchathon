# Independent catalog foundation

> Historical PR #11 record. Segment I0 integrates this catalog with the repaired scanner foundation; current catalog entry is `-fitcheck-catalog-internal`, while the original avatar flag remains avatar-only. The integrated manifest retains both elapsed-time and app-local preferences declarations. See [current integration routing, ownership and results](INTEGRATION_HANDOFF.md); the original base/gate and verification statements below describe the independent segment, not I0.

## Decisions before implementation

- Base: `main` at `562173f`, not the unfinished #8 → #9 → #10 stack. That stack remains unmerged and its Segment 1B physical LiDAR requirements remain blocked. The catalog does not need capture, avatar storage, geometry, or fit code.
- Reuse only the reviewed `AvatarExperienceFeatures.swift` gate from #8, unchanged: Debug compilation plus exact `-fitcheck-avatar-internal` opt-in. The internal root opens the catalog; normal/Release launch preserves the existing app. Later integration with the avatar branch has one explicit `RootView` composition point, not a second scanner/profile implementation.
- New catalog domain is separate from legacy `GarmentProfile` and `GarmentSizeVariant`: those contain measurement/fit inputs and fallback UUIDs, not authoritative retailer product/SKU identities.
- Use retailer-scoped stable product IDs, explicit variant IDs/options, exact minor-unit money with ISO currency, provenance/revisions, and explicit missing data. Never infer finished dimensions from S/M/L or a body recommendation chart.
- One small async repository boundary provides listing, lookup, and variant lookup. Start with validated local synthetic JSON embedded in Debug-only source; no backend, account system, network image loader, cart, checkout, or speculative service abstraction.
- Native SwiftUI browse/detail screens use clearly labelled no-photo placeholders (Apple SF Symbols), not stock retailer imagery. Selection is clothing color/size selection only. No body setup, avatar rendering, try-on, fit estimate, or numeric body information.
- All catalog implementation and synthetic fixture code compile out of Release. No scan data, stored avatar metadata, or legacy measurement preferences are used by the catalog.

## Implemented boundary

- `CatalogDocument` is schema-versioned and validates the entire incoming snapshot: required text, stable IDs, duplicate product/option/variant identities, duplicate color/size combinations, orphan references, money, media metadata and finished measurements. Unknown additive fields are ignored; malformed fields and unsupported schemas are not silently converted into sample products.
- Product identity is `(retailerID, productID)`. Variant IDs are unique within a retailer; identical IDs from different retailers remain distinct through their product context. Option IDs are separate from customer-facing size/color labels.
- Prices use nonnegative `Int64` minor units and an ISO currency code, never binary floating-point currency amounts. Presentation uses the currency's fraction digits and includes its code. Product-level price is explicitly **From**; a missing selected-variant price never inherits it.
- `CatalogFinishedMeasurements` accepts only positive finite finished-garment dimensions, explicit units and known source/revision/reference. Its JSON `values` is a named object, not Swift's alternating enum-key dictionary array. A body recommendation chart cannot populate it. Structural validation/provenance does not prove physical accuracy.
- `CatalogRepository` provides listing, scoped lookup and variant lookup. Empty listing, missing product/combination, unavailable source and failed/invalid data are distinct. `OfflineCatalogRepository` is an actor with a validated immutable snapshot/index; success is cached in memory, source failures remain retryable. No file or network adapter is hidden behind it.
- Presentation models own loading/retry and selection state. A color change invalidates selection; unknown/sold-out/discontinued options cannot be selected. Request generations discard late results. Detail lookup rejects another scoped product, and variant lookup rejects another SKU even when its option labels match.

## Offline collection and presentation

`SyntheticCatalog` contains three fictional `sample-studio` T-shirts: Everyday Tee exercises two colors, USD starting/variant prices and unavailable options; Weekend Tee has no supplied description or prices; Archive Tee is discontinued. Every sample has **no photos and no finished measurements**. Names, prices and stock states are fixtures, not retailer offers.

The opt-in catalog has a native navigable collection, detail screens, accessible named/selected color and size controls, retry/empty/unavailable states, and explicit missing-data copy. Generic Apple SF Symbols are clearly labelled photo placeholders, not garment previews. The catalog does not read or create an avatar; avatar viewing, try-on and fit remain unavailable.

Both list and detail use the injected repository. A future authorized adapter can replace the offline implementation without making the UI decode transport payloads. Remote/bundled media references can be represented by the domain; a real media loader is intentionally not implemented, and the current screens show placeholders.

## Privacy, rights and integration

The catalog has no camera/sensor, profile-store, disk-write, analytics, logging, upload or network dependency. Its only cache is in-memory synthetic catalog data. No retailer imagery was downloaded; no photos, depth, segmentation, landmarks or identifying body data were added to source, fixtures or commits. UI test attachments contain only synthetic catalog screens.

The app privacy manifest declares no tracking/collected data and the existing app-local UserDefaults use (`CA92.1`). It is not a claim that the preserved legacy prototype has received production privacy approval.

[The retailer contract](RETAILER_CATALOG_CONTRACT.md) separates device responsibilities from future authorized service responsibilities. Retailer credentials, authoritative price/stock normalization and media entitlements may belong in that future service; sensitive scan data stays on-device. No API permission, accounts, backend, API secrets or retailer integration is implemented or assumed.

## Known limits and release decision

- This is an internal offline foundation, not an approved live storefront. Availability is fixture state, selection reserves nothing, and no purchase/cart exists.
- No real product media loader, pagination, live refresh, account or cache persistence is implemented. Add these only against an authorized retailer contract; errors must never fall back to fictional stock.
- Product specification provenance is metadata, not independent verification of dimensions, media rights or fit. Real measurements and media require retailer review.
- Normal/Release launch preserves `main`'s legacy prototype. This branch does not approve that manual/score-based flow as the future customer journey.
- Physical scanner registration, front/side feasibility, continuity and device lifecycle requirements remain in draft PR #10 / Segment 1B. No physical scanner scenario was run here. Simulator catalog success cannot establish scan accuracy or authorize geometry/try-on work.

## Verification — 2026-10-20

Environment: Xcode 26.5 (`17F42`), XcodeGen 2.46.0, iPhone 17 Pro simulator, iOS 26.5 (`23F77`), destination `7F050083-C268-4F37-B730-C677F19A88EA`.

| Check | Observed result |
| --- | --- |
| Clean `main` baseline before implementation | 46 passed, 0 failures/skips |
| XcodeGen + integrated Debug build/test | 70 passed: 66 unit + 4 UI; 0 failures/skips |
| Normal unsigned iPhone SDK Release build | Passed; no testability override |
| Release gate unit test + actual launch/navigation isolation UI test | 2 passed, 0 failures/skips |
| Built-artifact isolation | Catalog type and synthetic-fixture markers present in Debug runtime image, absent from normal Release executable |
| Privacy manifest | `plutil -lint` passed; declaration present in built Release app |
| Actual simulator visual smoke | Reviewed five captured screens: collection, detail/photo placeholder, selected cream M with USD 20 price, missing information, discontinued option |
| Physical scanner validation | Not executed; hardware unavailable and Segment 1B remains blocked |

The first integrated run found an incorrect new test expectation: an unavailable fixture had no price, while the helper's expected copy supplied USD 18. The implementation correctly preserved the missing price; the assertion now expects that actual fixture value. No existing legacy assertion was weakened or disabled.

Two additional regression tests failed before the identity guards: a lookup could display another retailer's product, and matching option IDs could authorize a foreign SKU. The small presentation-boundary corrections reject both; the full final suite includes the now-passing tests. Other coverage includes duplicate IDs/combinations, malformed/unsupported snapshots, measurement basis/units/provenance, exact USD/JPY/KWD presentation, empty/missing/unavailable/error distinctions, source-error recovery, selection invalidation and delayed variant results after a color change.

Commands actually executed from the repository:

```sh
xcodegen generate
plutil -lint Sources/Support/PrivacyInfo.xcprivacy

xcodebuild -project FitCheck.xcodeproj -scheme FitCheck -configuration Debug \
  -destination 'platform=iOS Simulator,id=7F050083-C268-4F37-B730-C677F19A88EA' \
  -derivedDataPath /tmp/fitcheck-catalog-derived \
  -resultBundlePath /tmp/fitcheck-catalog-debug-final.xcresult \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test -quiet

xcodebuild -project FitCheck.xcodeproj -scheme FitCheck -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/fitcheck-catalog-release-iphone \
  -resultBundlePath /tmp/fitcheck-catalog-release-build.xcresult \
  CODE_SIGNING_ALLOWED=NO build -quiet

xcodebuild -project FitCheck.xcodeproj -scheme FitCheck -configuration Release \
  -destination 'platform=iOS Simulator,id=7F050083-C268-4F37-B730-C677F19A88EA' \
  -derivedDataPath /tmp/fitcheck-catalog-release-simulator \
  -resultBundlePath /tmp/fitcheck-catalog-release-isolation.xcresult \
  -parallel-testing-enabled NO \
  -only-testing:FitCheckTests/CatalogIsolationTests \
  -only-testing:FitCheckUITests/CatalogUITests/testNormalLaunchAndReleaseOptInRemainIsolated \
  ENABLE_TESTABILITY=YES CODE_SIGNING_ALLOWED=NO test -quiet
```

The Release simulator **test** invocation enables testability only to access the gate from `@testable` tests. The separately built normal iPhone Release artifact does not. Its `strings -a` output lacked `CatalogRootView`, `CatalogMoney`, `OfflineCatalogRepository`, `sample-studio` and `local-synthetic-fixture`; the Debug `FitCheck.debug.dylib` contained all five as a positive control.

Xcode emitted a Release interface-orientation/full-screen configuration warning and simulator debugger-version log messages. They were not suppressed; all listed tests executed. Manual VoiceOver, largest Dynamic Type and additional-device layout review remain unverified; automated tests exercised accessible names/IDs, selected values and disabled options.

**GO for the independent internal catalog foundation.** Not approval for a live storefront, scanner accuracy, avatar geometry, try-on or fit prediction. Retailer permission/data/media review and the approved avatar-first customer journey remain separate prerequisites.

## Exact changed files

| File | Why |
| --- | --- |
| `Sources/Catalog/CatalogModels.swift` | Portable versioned domain, strict snapshot validation, exact money, media/measurement provenance |
| `Sources/Catalog/CatalogRepository.swift` | Replaceable async boundary and explicit lookup/error outcomes |
| `Sources/Catalog/OfflineCatalogRepository.swift` | Actor-owned validated offline snapshot/index and retryable source errors |
| `Sources/Catalog/SyntheticCatalog.swift` | Clearly fictional Debug-only collection with missing/unavailable cases |
| `Sources/Catalog/CatalogViewModels.swift` | Loading/retry/selection ownership, stale-result and identity rejection |
| `Sources/Catalog/CatalogViews.swift` | Native browsing/details, accessible options, honest placeholders and missing states |
| `Sources/AvatarNext/AvatarExperienceFeatures.swift` | Reuse #8's reviewed Debug opt-in gate unchanged, without scanner/profile dependencies |
| `Sources/Views/RootView.swift` | Single internal composition point; unchanged normal/Release legacy route |
| `Sources/Support/PrivacyInfo.xcprivacy` | Declare existing app-local preferences reason and no tracking/collection |
| `Tests/CatalogModelTests.swift` | Identity, duplicate/malformed data, measurement and exact currency boundaries |
| `Tests/CatalogRepositoryTests.swift` | Scoped lookups, unavailable/empty/errors and retry recovery |
| `Tests/CatalogPresentationTests.swift` | State/selection transitions, delayed results and mismatched identities |
| `Tests/CatalogIsolationTests.swift` | Exact Debug opt-in and unconditional Release rejection |
| `UITests/CatalogUITests.swift` | Real navigation, accessible selection, missing/unavailable states and Release launch isolation |
| `Docs/CATALOG_FOUNDATION.md` | Base/architecture decisions, actual evidence, scope and decision |
| `Docs/RETAILER_CATALOG_CONTRACT.md` | Minimum authorized contract, rights/privacy and device/service responsibilities |
| `README.md` | Internal launch instructions and clear distinction from the preserved legacy prototype |
