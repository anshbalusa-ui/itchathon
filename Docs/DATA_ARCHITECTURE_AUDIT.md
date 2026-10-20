# Data architecture audit — device foundation and future services

This is a boundary review of actual PR #8/#9 source, not a backend implementation or a promise that unknown retailer APIs need no future design. No cloud, account model, database, transport client, repository registry, dependency, or Android runtime was added.

## Existing architecture and evidence

| Boundary | Actual implementation | Assessment / required constraint |
| --- | --- | --- |
| Capture hardware | `AppleScanCamera` owns ARKit preview/session/permissions on the main actor | Keep Apple APIs in this adapter. Camera identity now scopes teardown and callbacks; an obsolete preview cannot stop its replacement. |
| Analysis | `AppleScanFrameProcessor` serial queue, `AvatarFrameAnalyzer`, `AppleScanEvidence` | One physical analysis job, read-only SDK buffers, explicit borrow/lock lifetime. No network or persistence. Swift unchecked Sendable wrappers rely on immutable buffers and queue confinement, not arbitrary concurrent mutation. |
| Capture policy | `AvatarCaptureCoordinator`, plain `ScanCaptureContracts` | Camera-independent timestamps, quality, motion, and view sequence. Continuity breaks now invalidate the saved front. This is observational input, not identity verification or reliable reconstructed geometry. |
| Pair ownership | Private model front/pair, attempt generations, explicit discard | The model constructs pairs only from accepted current-attempt results. `ScanEvidencePair` is not a signed proof, upload DTO, biometric assertion, or permission to generate an avatar. Do not bypass that owner lifecycle or treat nil rejection as real-world accuracy. |
| Durable avatar metadata | Async injectable `AvatarProfilePersisting`, protected actor repository | Retain version-first decode, typed invalid/corrupt/unsupported errors, real I/O failures, protected atomic publication, per-file backup exclusion. Fixed destructive deletion caused by cached resource values; no schema/storage rewrite. |
| Preview eligibility | Pure record validation and renderer compatibility callback | Structural metadata is separate from scan accuracy and actual renderer compatibility. Default supports no renderer. Never auto-convert legacy manual measurements or provisional scan pairs to approved profiles. |
| Legacy preferences | Main-actor `ProfileStore`, Codable body/garment/chart models in app UserDefaults | Compatibility boundary only. Decode failures currently become absent/default data via `try?`; this behavior was not migrated into the new repository. Do not reuse it as a backend/account store or silently synchronize defaults. |
| Legacy fit/catalog data | Pure `FitEngine`, local `GarmentSizeChart` / `GarmentProfile` | No retailer API exists. Metre units and finished-garment/body-recommendation distinction are explicit; legacy scores are not validated 3D fit. Local/random fallback UUIDs are not authoritative retailer SKU/version identifiers. |
| UI | SwiftUI state and native camera representation | Business decisions stay in model/policy. Network authentication, product parsing, retries, and secrets must not be put into view bodies or camera delegates. |

## Responsibilities that remain on-device

- Permission, capability, consent presentation, capture lifecycle, privacy cover, sensor orientation/calibration, same-frame association, and ephemeral buffer ownership.
- Raw RGB/depth/confidence/person masks and identifying camera/landmark observations. Under the current privacy requirement these are never a backend upload payload or a debug-logging payload.
- Local capture rejection, unknown-view states, and safe cancellation. A remote service cannot repair unproven registration or turn missing evidence into a valid body.
- Protected local profile access/deletion, renderer capability checks, and later rendering. Personalized geometry/fit work has not been implemented or approved by this audit.
- Mapping future network results to consumer-safe UI without measurements, body judgments, scores, or technical diagnostics. The preserved legacy Release UI is not yet this new customer journey.

## Responsibilities a future backend may own

These require a separately authorized, concrete integration; no interfaces or empty services were invented now.

| Responsibility | Future ownership / safety boundary |
| --- | --- |
| Accounts and authorization | Server validates identity and access; client uses a narrowly scoped authenticated session. Never trust a client-supplied owner ID as authorization. Credentials/tokens must not enter scanner evidence or ordinary preference fields. |
| Retailer catalog/products | Server-side authorized retailer adapters manage product/SKU identity, garment measurement basis/units, material and asset versions, freshness, availability, and retailer permission. Device receives validated presentation/domain data. Never infer garment measurements from a size label or convert body recommendation charts into finished garments. |
| Asset/schema compatibility | A reviewed versioned contract identifies approved model/control schemas and asset licenses. Keep code licensing distinct from 3D asset licensing. A nonblank asset string is not compatibility evidence. |
| Synchronization | Only explicitly approved, minimized data with ownership, consent, version/conflict policy, retention, and deletion semantics. Current raw/identifying capture data must not be uploaded. Do not reuse `ScanFrameMetadata: Codable` as approval for transport; Codable is not a privacy boundary. |
| Error/recovery contract | Distinguish authentication, authorization, offline/transport, rate limits, unsupported schema, invalid domain data, and missing resource. Do not turn backend failures into an empty successful profile or reuse camera quality rejections for server errors. |
| Operations | Secrets, authorized upstream access, rate enforcement, schema validation, and retention policy are backend concerns. None belongs in shipped app constants or this scanner repair. |

## Account and concurrent-store readiness — explicit gaps

The current avatar file is **device/app-container scoped**, with no authenticated owner, account partition, or sync state. The legacy defaults keys are also app-global. This is appropriate only for the present local experience, not multi-account production.

Before adding accounts or sync, define and test ownership-keyed local storage, migration, sign-out/erase behavior, protection and backup policy, cache invalidation, and cross-account read prevention. Do not silently attach an anonymous device profile to whichever account next signs in.

The current repository serializes operations per actor, not across independently constructed actors or processes. It uses one reserved pending filename, including recovery cleanup. Default view construction can create separate repository instances; current application capture does not save profiles, and no actual overlapping profile writer was reproduced. A deterministic post-write interleaving is not exposed by the current seam; no timing-only stress test or production hook was added merely to force a change. This remains a design risk: establish one coordinated owner or a reviewed filesystem coordination strategy before concurrent writers, multiple scenes, account namespaces, or sync are introduced. Do not claim distributed transactions or cross-process safety.

## Android and portable-core boundary

`ScanCaptureContracts`, coordinator, and depth policy compile without ARKit, Vision, CoreVideo, or UIKit. Metadata specifies scalar dimensions/units, opaque sensor timestamps, separate local freshness clocks, rotation/origin conventions, calibration, confidence, and row strides; buffer providers borrow memory synchronously.

A future Android adapter must provide genuinely equivalent, calibrated observations and capability/unknown states. Missing LiDAR/confidence must not be synthesized. Backend DTOs should use stable explicit IDs, schema versions, declared units, and optional/unknown evidence, rather than platform object identity or encoded native camera objects. Whether to share code or port the small policy is a future platform decision; no Android implementation or sensor parity is claimed.

## Decisions now

1. Repair demonstrated safety/ownership/continuity defects without replacing working persistence or domain models.
2. Preserve legacy behavior and stored data, but do not call its manual-measurement/score UI approved for retailer release.
3. Keep camera and identifying capture data on-device; no network path added.
4. Keep local and eventual remote persistence behind the existing narrow responsibility boundaries; introduce concrete adapters only when an authorized API/account contract exists.
5. Require physical registration and usable ordinary front/side evidence before geometry research. Source separation and passing synthetic tests do not establish body accuracy.
