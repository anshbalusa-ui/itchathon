# FitCheck 2.0 — Coding-agent story prompts

**Usage:** review the matching story in [AVATAR_MVP_STORIES.md](AVATAR_MVP_STORIES.md); give one prompt at a time to an agent with GitHub + Xcode access. Prefer a new branch/draft PR per story. Do not run every story in parallel because the scanner and avatar data contracts have dependencies.

## Reusable instruction block

The following instructions are deliberately included in every prompt so each is self-contained:

- Work inside `anshbalusa-ui/itchathon` (SwiftUI + XcodeGen `project.yml`), not a new app.
- Read the product requirements, architecture and story backlog from `Docs/AVATAR_MVP_*.md`. If the docs PR is not merged, read them on branch `docs/avatar-first-mvp-spec-and-stories-20261019`.
- Inspect the actual existing files before changing them. `main` has the manual flow; experimental scanner code exists in draft PR #5, branch `feature/avatar-first-scanner-20261019`.
- Keep scanner, avatar mesh, fit inference and garment visualization separate. The new customer experience is **create an avatar first → save it → choose clothing → approximate try-on and conservative fit copy**.
- No visible body measurements, numbers, scores, measuring instructions or manual body-point marking in the customer journey; no judgment of body appearance.
- Never fabricate body geometry, fit accuracy, a camera result, ecommerce integration, or successful build/tests.
- No raw camera frames, depth/masks, personal body images or secrets in persistent storage, GitHub or logs.
- Deliver a focused diff, tests, real-device checklist, and an honest list of limitations. If Xcode is unavailable, say build unverified.

## Master prompt — turn a requirement into the next well-scoped story

```text
Act as FitCheck's technical product manager and senior iOS engineer. Read:
Docs/AVATAR_MVP_REQUIREMENTS.md,
Docs/AVATAR_MVP_ARCHITECTURE.md,
Docs/AVATAR_MVP_STORIES.md,
and the live repository/PR state.

Given a requested feature, propose ONE small vertical user story for the avatar-first MVP.
Return: user value, exact scope/out of scope, existing files to inspect,
proposed file changes, inputs/outputs, dependencies, failure and privacy cases,
test plan (unit/UI/real LiDAR device), measurable acceptance criteria,
risk/fallback, and one copy-ready coding-agent prompt.
Don't assume unmerged scanner code is production-ready. No body measurements or
scores in customer UI. Distinguish representative avatar/garment visuals from
validated fit inference. Never invent capabilities or say tests passed without logs.
Don't implement or merge code unless the user separately asks you to.
```

## Ready-to-run implementation prompts

### ST-00 — Baseline verification and guided scanner build

```text
You are implementing one story in the existing native SwiftUI FitCheck app (GitHub: anshbalusa-ui/itchathon). First inspect the live repo and read Docs/AVATAR_MVP_REQUIREMENTS.md, Docs/AVATAR_MVP_ARCHITECTURE.md and Docs/AVATAR_MVP_STORIES.md on the documentation branch if they are not yet merged. Preserve working manual-demo functionality on main unless this story explicitly replaces part of the new avatar path. Coordinate with unmerged scanner draft PR #5; do not assume it compiles. Work on a focused branch/PR; don't silently merge.

Global constraints: avatar-first customer flow; no numbers, body measurements, scores, tape instructions or body judgments in customer UI; no fake scans or measurements; no raw images, videos, segmentation masks or depth buffers saved/uploaded or committed; no unsupported garment-fit or physics claims. Keep failure/unknown states explicit.

At the end report file changes, Xcode build/test command + actual results (or say not run), real LiDAR iPhone validation steps, limitations and next dependency.

STORY ST-00 — Baseline verification and guided scanner build

Goal: validate and repair the current experimental scanner from draft PR #5, NOT create an avatar or fit clothes.

1. Check out the PR #5 feature branch or create a repair branch based on it. Review sources in Sources/Scanning/, the original Sources/BodyScan/ scanner, project.yml, and the existing Tests/.
2. Run xcodegen generate, enumerate local Xcode destinations, and build/test with an actual available simulator. Fix compile errors, threading/lifecycle issues, Vision request/orientation incompatibilities, and test failures. Preserve baseline existing features.
3. On a real LiDAR iPhone Pro, verify permission handling, full-person front and side detection, camera tracking/loss/recovery, no-person/cropped subject, and cancel/retake. Log only abstract scan status, never frames or body measurements.
4. If camera hardware isn't available, stop at simulation-safe work and mark device validation blocked. Don't claim real-device success.
5. Add a concise capture-state diagnostic checklist; no scanner success claim based on session-wide depth alone.

Acceptance: code compiles when actual Xcode is available, tests run and are reported; guided scan may complete only with actual person/depth/stability evidence; retry/cancel is reliable. Open or update a draft PR with observations and unresolved risks.
```

### ST-01 — Person-depth alignment and orientation gating

```text
You are implementing one story in the existing native SwiftUI FitCheck app (GitHub: anshbalusa-ui/itchathon). First inspect the live repo and read Docs/AVATAR_MVP_REQUIREMENTS.md, Docs/AVATAR_MVP_ARCHITECTURE.md and Docs/AVATAR_MVP_STORIES.md on the documentation branch if they are not yet merged. Preserve working manual-demo functionality on main unless this story explicitly replaces part of the new avatar path. Coordinate with unmerged scanner draft PR #5; do not assume it compiles. Work on a focused branch/PR; don't silently merge.

Global constraints: avatar-first customer flow; no numbers, body measurements, scores, tape instructions or body judgments in customer UI; no fake scans or measurements; no raw images, videos, segmentation masks or depth buffers saved/uploaded or committed; no unsupported garment-fit or physics claims. Keep failure/unknown states explicit.

At the end report file changes, Xcode build/test command + actual results (or say not run), real LiDAR iPhone validation steps, limitations and next dependency.

STORY ST-01 — Person-depth alignment and orientation gating

Prerequisite: ST-00 scan branch has a verified build. Goal: ensure front/side frames contain usable, correctly aligned person-specific depth.

1. Inspect ARFrame.capturedImage, sceneDepth, confidenceMap, camera intrinsics, image orientation and Vision coordinate conventions.
2. Introduce an explicit alignment component that maps person masks/landmarks into the depth-map coordinate system, accounting for image/depth resolutions, orientation and camera transforms. Do not assume equal pixel dimensions or coordinate orientation.
3. Evaluate depth confidence on the actual segmented person, not across the whole scene. Reject stale frame pairs, cropped bodies, moving people and untrusted depth.
4. Implement conservative front/side quality guidance, accommodating expected side-view joint occlusion; do not infer exact orientation from an arbitrary single landmark.
5. Add deterministic transform and gating tests with synthetic buffers, plus a real-device evidence checklist. Diagnostic overlays are developer-only and never save/display real scans in customer mode.

Acceptance: successful capture requires person-associated depth of usable quality; valid frame mappings are demonstrable, questionable orientation triggers retry; actual Xcode/device results are reported.
```

### ST-02 — Internal geometry estimator with provenance

```text
You are implementing one story in the existing native SwiftUI FitCheck app (GitHub: anshbalusa-ui/itchathon). First inspect the live repo and read Docs/AVATAR_MVP_REQUIREMENTS.md, Docs/AVATAR_MVP_ARCHITECTURE.md and Docs/AVATAR_MVP_STORIES.md on the documentation branch if they are not yet merged. Preserve working manual-demo functionality on main unless this story explicitly replaces part of the new avatar path. Coordinate with unmerged scanner draft PR #5; do not assume it compiles. Work on a focused branch/PR; don't silently merge.

Global constraints: avatar-first customer flow; no numbers, body measurements, scores, tape instructions or body judgments in customer UI; no fake scans or measurements; no raw images, videos, segmentation masks or depth buffers saved/uploaded or committed; no unsupported garment-fit or physics claims. Keep failure/unknown states explicit.

At the end report file changes, Xcode build/test command + actual results (or say not run), real LiDAR iPhone validation steps, limitations and next dependency.

STORY ST-02 — Internal geometry estimator with provenance

Prerequisite: ST-01 has validated person-depth alignment. Goal: produce truthful geometry evidence for later avatar personalization without customer measurements.

1. Inspect existing BodyGeometry.swift, BodyProfile.swift, DepthMeasurement.swift and measurement origins. Create a separate derived-geometry model with source/provenance, observed/approximate/unavailable state, and quality reason for each region.
2. Estimate only geometry that the front/side LiDAR+mask data can support using calibrated camera intrinsics and explicitly documented assumptions.
3. Never transform a 2D width into a claimed circumference without a defensible model and validation; missing chest/hip values remain unavailable.
4. Implement repeatability tests with synthetic known geometries and reject invalid/ambiguous values. Draft a private, consent-based real-reference-measurement test procedure; do not collect identifying scan imagery.
5. Keep all internal meters/quality values off the customer screen, but make unavailable data detectable by downstream fit inference.

Acceptance: real capture can produce an explicitly incomplete but typed internal geometry profile when possible; no invented measurements; repeatability and reference-validation limitations documented.
```

### ST-03 — Open-source 3D asset audit and export

```text
You are implementing one story in the existing native SwiftUI FitCheck app (GitHub: anshbalusa-ui/itchathon). First inspect the live repo and read Docs/AVATAR_MVP_REQUIREMENTS.md, Docs/AVATAR_MVP_ARCHITECTURE.md and Docs/AVATAR_MVP_STORIES.md on the documentation branch if they are not yet merged. Preserve working manual-demo functionality on main unless this story explicitly replaces part of the new avatar path. Coordinate with unmerged scanner draft PR #5; do not assume it compiles. Work on a focused branch/PR; don't silently merge.

Global constraints: avatar-first customer flow; no numbers, body measurements, scores, tape instructions or body judgments in customer UI; no fake scans or measurements; no raw images, videos, segmentation masks or depth buffers saved/uploaded or committed; no unsupported garment-fit or physics claims. Keep failure/unknown states explicit.

At the end report file changes, Xcode build/test command + actual results (or say not run), real LiDAR iPhone validation steps, limitations and next dependency.

STORY ST-03 — Open-source 3D asset audit and export

Goal: produce a legally usable, performant avatar base mesh and simple T-shirt template; do not start photorealistic cloth simulation.

1. Evaluate bundled CC0 MakeHuman/MPFB assets plus any independently licensed candidate. Examine source code license versus asset/output license separately; verify any third-party clothing asset terms before redistribution.
2. Using Blender/MakeHuman or another available offline pipeline, create a lightweight neutral avatar and a corresponding shirt mesh. Select a coordinate/scale convention and a RealityKit-compatible asset export format.
3. Record asset provenance, version, license, export tool/settings, approximate complexity and any redistribution notices in an asset manifest.
4. Prototype loading/rendering in a tiny native iPhone test scene if environment permits. Verify that the intended shape-adjustment method survives the export format; do not assume morph targets or skinning automatically work.
5. Check in only permitted compact 3D assets, not software bundles, photos of people or fonts.

Acceptance: approved renderable base avatar/shirt assets or a documented fallback; license manifest reviewed; actual iPhone load and rotation status recorded.
```

### ST-04 — 3D avatar renderer

```text
You are implementing one story in the existing native SwiftUI FitCheck app (GitHub: anshbalusa-ui/itchathon). First inspect the live repo and read Docs/AVATAR_MVP_REQUIREMENTS.md, Docs/AVATAR_MVP_ARCHITECTURE.md and Docs/AVATAR_MVP_STORIES.md on the documentation branch if they are not yet merged. Preserve working manual-demo functionality on main unless this story explicitly replaces part of the new avatar path. Coordinate with unmerged scanner draft PR #5; do not assume it compiles. Work on a focused branch/PR; don't silently merge.

Global constraints: avatar-first customer flow; no numbers, body measurements, scores, tape instructions or body judgments in customer UI; no fake scans or measurements; no raw images, videos, segmentation masks or depth buffers saved/uploaded or committed; no unsupported garment-fit or physics claims. Keep failure/unknown states explicit.

At the end report file changes, Xcode build/test command + actual results (or say not run), real LiDAR iPhone validation steps, limitations and next dependency.

STORY ST-04 — 3D avatar renderer

Prerequisite: ST-03 delivers a legal tested mesh. Goal: create an isolated reusable native iOS viewer.

1. Implement an AvatarRenderer and SwiftUI AvatarPreviewView using RealityKit or another verified compatible iOS renderer.
2. Load the chosen asset asynchronously; support rotation, reset view, accessible non-gesture rotation controls, neutral lighting, and clear loading/error states.
3. Preserve fixed realistic constraints for scale and camera placement. Handle missing/corrupt assets without crashing. Keep view lifecycle/cached assets bounded.
4. Do not pretend the initial generic avatar is personalized from the camera; show honest preview copy.
5. Test asset loading, scene state updates and accessibility. Run device rendering/performance observations and report them.

Acceptance: a rotatable, generic avatar renders on a real iPhone; no false claim that it reflects a scan; code is cleanly separated from scanning.
```

### ST-05 — Map evidence to supported avatar parameters

```text
You are implementing one story in the existing native SwiftUI FitCheck app (GitHub: anshbalusa-ui/itchathon). First inspect the live repo and read Docs/AVATAR_MVP_REQUIREMENTS.md, Docs/AVATAR_MVP_ARCHITECTURE.md and Docs/AVATAR_MVP_STORIES.md on the documentation branch if they are not yet merged. Preserve working manual-demo functionality on main unless this story explicitly replaces part of the new avatar path. Coordinate with unmerged scanner draft PR #5; do not assume it compiles. Work on a focused branch/PR; don't silently merge.

Global constraints: avatar-first customer flow; no numbers, body measurements, scores, tape instructions or body judgments in customer UI; no fake scans or measurements; no raw images, videos, segmentation masks or depth buffers saved/uploaded or committed; no unsupported garment-fit or physics claims. Keep failure/unknown states explicit.

At the end report file changes, Xcode build/test command + actual results (or say not run), real LiDAR iPhone validation steps, limitations and next dependency.

STORY ST-05 — Map evidence to supported avatar parameters

Prerequisites: ST-02 typed geometry + ST-04 viewer. Goal: make only justified avatar adjustments.

1. Define a small AvatarParameterMapper with source confidence and clamp/sanity rules for supported avatar parameters. Review actual mesh topology/morph support; do not assume arbitrary mesh deformation works.
2. Translate observed/validated approximate dimensions to only compatible adjustments, leaving unknown parameters unspecified. Preserve neutral shapes rather than guessing unseen body features.
3. Prove with synthetic fixtures that changing a supported parameter changes the rendered avatar in the expected direction without distortion.
4. Test scan-driven rendering on a real LiDAR iPhone if hardware available; record where it is illustrative and which dimensions cannot be inferred.
5. Keep values invisible to customer; no judgmental body descriptors.

Acceptance: reliable observed features alter visible avatar shape; unsupported information never becomes made-up measurements; if personalization is not validated, display an explicitly illustrative avatar.
```

### ST-06 — Reusable on-device avatar and delete

```text
You are implementing one story in the existing native SwiftUI FitCheck app (GitHub: anshbalusa-ui/itchathon). First inspect the live repo and read Docs/AVATAR_MVP_REQUIREMENTS.md, Docs/AVATAR_MVP_ARCHITECTURE.md and Docs/AVATAR_MVP_STORIES.md on the documentation branch if they are not yet merged. Preserve working manual-demo functionality on main unless this story explicitly replaces part of the new avatar path. Coordinate with unmerged scanner draft PR #5; do not assume it compiles. Work on a focused branch/PR; don't silently merge.

Global constraints: avatar-first customer flow; no numbers, body measurements, scores, tape instructions or body judgments in customer UI; no fake scans or measurements; no raw images, videos, segmentation masks or depth buffers saved/uploaded or committed; no unsupported garment-fit or physics claims. Keep failure/unknown states explicit.

At the end report file changes, Xcode build/test command + actual results (or say not run), real LiDAR iPhone validation steps, limitations and next dependency.

STORY ST-06 — Reusable on-device avatar and delete

Prerequisite: ST-05 profile/parameter contracts. Goal: scan once, reuse for shopping later.

1. Design a schema-versioned Codable AvatarProfile that stores only derived metadata and approved avatar parameters, not raw photos, video, depth buffers or segmentation masks.
2. Implement a local AvatarProfileStore with atomic save/load, corruption-safe defaults, version migration, explicit delete and rescan replacement. Consider iOS app-protected file storage.
3. Ensure teardown/cancellation releases temporary in-memory camera buffers. Never transmit body profile anywhere.
4. Wire a provisional "My Avatar" status screen; rehydrate 3D renderer from a profile on cold launch. Make delete and rescan easy.
5. Test save/load across app relaunch, missing files, unsupported schema, failed saves, deletion and old manual-profile coexistence.

Acceptance: saved avatar opens without scanning again; permanent local profile removal works; no raw scan data persists.
```

### ST-07 — Offline mock clothing catalog and data contract

```text
You are implementing one story in the existing native SwiftUI FitCheck app (GitHub: anshbalusa-ui/itchathon). First inspect the live repo and read Docs/AVATAR_MVP_REQUIREMENTS.md, Docs/AVATAR_MVP_ARCHITECTURE.md and Docs/AVATAR_MVP_STORIES.md on the documentation branch if they are not yet merged. Preserve working manual-demo functionality on main unless this story explicitly replaces part of the new avatar path. Coordinate with unmerged scanner draft PR #5; do not assume it compiles. Work on a focused branch/PR; don't silently merge.

Global constraints: avatar-first customer flow; no numbers, body measurements, scores, tape instructions or body judgments in customer UI; no fake scans or measurements; no raw images, videos, segmentation masks or depth buffers saved/uploaded or committed; no unsupported garment-fit or physics claims. Keep failure/unknown states explicit.

At the end report file changes, Xcode build/test command + actual results (or say not run), real LiDAR iPhone validation steps, limitations and next dependency.

STORY ST-07 — Offline mock clothing catalog and data contract

Goal: let customers browse items after creating an avatar, without requiring Ben's store API now.

1. Define CatalogProduct, GarmentVariant and CatalogRepository contracts plus a dependency-injected MockCatalogRepository.
2. Use a handful of explicitly synthetic T-shirt entries with locally licensed sample images and finished-garment dimensions ONLY where identified as mock measurements. Distinguish finished-garment specs from body-size charts.
3. Add product list and detail UI that can be reused after profile creation. Handle no network, no data, missing image, unsupported category and missing measurement cases.
4. Store future external product IDs and availability fields without hardcoding a specific ecommerce platform.
5. Test predictable listing and variant behavior; do not treat sample values as Ben's real product data.

Acceptance: products browse offline, data source is swappable, no hidden dependency on live store or made-up real-world sizing facts.
```

### ST-08 — Prepared T-shirt on avatar

```text
You are implementing one story in the existing native SwiftUI FitCheck app (GitHub: anshbalusa-ui/itchathon). First inspect the live repo and read Docs/AVATAR_MVP_REQUIREMENTS.md, Docs/AVATAR_MVP_ARCHITECTURE.md and Docs/AVATAR_MVP_STORIES.md on the documentation branch if they are not yet merged. Preserve working manual-demo functionality on main unless this story explicitly replaces part of the new avatar path. Coordinate with unmerged scanner draft PR #5; do not assume it compiles. Work on a focused branch/PR; don't silently merge.

Global constraints: avatar-first customer flow; no numbers, body measurements, scores, tape instructions or body judgments in customer UI; no fake scans or measurements; no raw images, videos, segmentation masks or depth buffers saved/uploaded or committed; no unsupported garment-fit or physics claims. Keep failure/unknown states explicit.

At the end report file changes, Xcode build/test command + actual results (or say not run), real LiDAR iPhone validation steps, limitations and next dependency.

STORY ST-08 — Prepared T-shirt on avatar

Prerequisites: ST-03 avatar/shirt assets, ST-04 viewer, ST-07 catalog. Goal: basic interactive illustrative try-on.

1. Define a garment-render-asset resolver mapping selected sample product/variant to a prepared 3D T-shirt mesh and materials.
2. Attach the garment to the avatar with correct coordinate and scaling conventions; avoid obviously broken intersections where possible without implementing cloth physics.
3. Switch items/colors on selection without resetting avatar parameters or leaking render resources.
4. Offer a simple neutral fallback if a product has no matching 3D asset; label it illustrative.
5. Test repeated item switching, rotation, missing assets, and device rendering.

Acceptance: a chosen sample garment appears over the avatar and changes when a different item is selected; visual result is not described as exact fabric drape or precise fit.
```

### ST-09 — Conservative garment-region fit explanations

```text
You are implementing one story in the existing native SwiftUI FitCheck app (GitHub: anshbalusa-ui/itchathon). First inspect the live repo and read Docs/AVATAR_MVP_REQUIREMENTS.md, Docs/AVATAR_MVP_ARCHITECTURE.md and Docs/AVATAR_MVP_STORIES.md on the documentation branch if they are not yet merged. Preserve working manual-demo functionality on main unless this story explicitly replaces part of the new avatar path. Coordinate with unmerged scanner draft PR #5; do not assume it compiles. Work on a focused branch/PR; don't silently merge.

Global constraints: avatar-first customer flow; no numbers, body measurements, scores, tape instructions or body judgments in customer UI; no fake scans or measurements; no raw images, videos, segmentation masks or depth buffers saved/uploaded or committed; no unsupported garment-fit or physics claims. Keep failure/unknown states explicit.

At the end report file changes, Xcode build/test command + actual results (or say not run), real LiDAR iPhone validation steps, limitations and next dependency.

STORY ST-09 — Conservative garment-region fit explanations

Prerequisites: ST-02 sourced geometry + ST-07 real/synthetic garment dimension types. Goal: evidence-based, simple fit language, not visible math.

1. Design FitEstimationService that accepts observed/approximate/missing scan regions, product's finished-garment size data and explicit provenance. Do NOT require a favorite garment as the current FitEngine does.
2. Evaluate physical garment ease internally only for supported regions and tested assumptions. Review current FitEngine.swift only for reusable safe parts; its prototype signed scores are not validated for this new journey.
3. Return a typed per-region label (snug, comfortable, relaxed, unknown) and a rationale, including UNKNOWN when data, validation or chart basis is inadequate. Do not invent universal numerical thresholds or claim scientific accuracy.
4. Map labels to neutral garment-focused copy. Never show raw measurements, scores, confidence percentages or body ratings in the shopper UI.
5. Unit test complete, incomplete, inconsistent, body-size-chart-only, wrong garment type and physically implausible cases.

Acceptance: all unsupported cases return unknown; fit feedback is clearly a provisional estimate; sample data can demonstrate the entire UI without posing as a validated retail recommendation.
```

### ST-10 — End-to-end avatar-first UX

```text
You are implementing one story in the existing native SwiftUI FitCheck app (GitHub: anshbalusa-ui/itchathon). First inspect the live repo and read Docs/AVATAR_MVP_REQUIREMENTS.md, Docs/AVATAR_MVP_ARCHITECTURE.md and Docs/AVATAR_MVP_STORIES.md on the documentation branch if they are not yet merged. Preserve working manual-demo functionality on main unless this story explicitly replaces part of the new avatar path. Coordinate with unmerged scanner draft PR #5; do not assume it compiles. Work on a focused branch/PR; don't silently merge.

Global constraints: avatar-first customer flow; no numbers, body measurements, scores, tape instructions or body judgments in customer UI; no fake scans or measurements; no raw images, videos, segmentation masks or depth buffers saved/uploaded or committed; no unsupported garment-fit or physics claims. Keep failure/unknown states explicit.

At the end report file changes, Xcode build/test command + actual results (or say not run), real LiDAR iPhone validation steps, limitations and next dependency.

STORY ST-10 — End-to-end avatar-first UX

Prerequisites: ST-06 saved avatar, ST-07 catalog, ST-08 visual shirt, ST-09 fit copy. Goal: deliver the flow agreed with the store owner.

1. Inspect HomeView, RootView, BodyProfileView, ProfileStore and existing scanner and tests.
2. Make avatar creation the first-launch destination. After saved avatar: home shows avatar + Explore; tapping a product opens try-on and estimated fit explanation.
3. Keep the legacy manual flow reachable only as a deliberate developer/legacy path until old tests and demo are safely migrated; do not silently delete working functionality.
4. Eliminate body measurements/scores, mathematical terms and manual marker placement from the NEW customer journey; don't hide the fact that try-on is an estimate.
5. Implement permissions, re-scan, delete, loading, unavailable geometry, unsupported device, VoiceOver/accessible buttons and navigation fallbacks.
6. Add UI tests for first-time, returning, delete, scan-failure and mock garment selection.

Acceptance: avatar-first journey works on device end to end; no numbers/manual measuring in customer-facing surfaces; no false success or fit promises.
```

### ST-11 — Integration QA, privacy audit and Ben demo

```text
You are implementing one story in the existing native SwiftUI FitCheck app (GitHub: anshbalusa-ui/itchathon). First inspect the live repo and read Docs/AVATAR_MVP_REQUIREMENTS.md, Docs/AVATAR_MVP_ARCHITECTURE.md and Docs/AVATAR_MVP_STORIES.md on the documentation branch if they are not yet merged. Preserve working manual-demo functionality on main unless this story explicitly replaces part of the new avatar path. Coordinate with unmerged scanner draft PR #5; do not assume it compiles. Work on a focused branch/PR; don't silently merge.

Global constraints: avatar-first customer flow; no numbers, body measurements, scores, tape instructions or body judgments in customer UI; no fake scans or measurements; no raw images, videos, segmentation masks or depth buffers saved/uploaded or committed; no unsupported garment-fit or physics claims. Keep failure/unknown states explicit.

At the end report file changes, Xcode build/test command + actual results (or say not run), real LiDAR iPhone validation steps, limitations and next dependency.

STORY ST-11 — Integration QA, privacy audit and Ben demo

Prerequisites: ST-00 through ST-10 complete/explicitly deferred. Goal: document the MVP's actual working capabilities, not its intended ones.

1. Create a physical LiDAR iPhone checklist for good/poor light, motion, partial person, depth loss, front/side, camera denied, cancel, app background, memory pressure, cold relaunch, profile delete and missing garment data.
2. Run XcodeGen + real Xcode tests, record output, device model/OS, and inspect crashes/timeout. Confirm no camera image/depth/mask/profile data is sent to external services or unintentionally written.
3. Manually test complete flow: onboarding -> guided scan -> avatar -> saved profile -> sample catalog -> garment render -> fit labels or unknown.
4. Check accuracy with controlled references only where permission is given. Don't claim calibration based on UI appearance.
5. Prepare a short honest Ben demo: explain what genuinely works, the illustrative parts, scan quality gaps, and what product data his store needs.
6. Create release-blocker checklist and mark deferred stories; do not merge broken capture code just to hit deadline.

Acceptance: all tested and untested claims distinguishable, issue list prioritized, privacy controls verified, app demo reproducible on target iPhone or explicitly downgraded to feasibility prototype.
```

### ST-12 — Ben storefront adapter design, not live integration

```text
You are implementing one story in the existing native SwiftUI FitCheck app (GitHub: anshbalusa-ui/itchathon). First inspect the live repo and read Docs/AVATAR_MVP_REQUIREMENTS.md, Docs/AVATAR_MVP_ARCHITECTURE.md and Docs/AVATAR_MVP_STORIES.md on the documentation branch if they are not yet merged. Preserve working manual-demo functionality on main unless this story explicitly replaces part of the new avatar path. Coordinate with unmerged scanner draft PR #5; do not assume it compiles. Work on a focused branch/PR; don't silently merge.

Global constraints: avatar-first customer flow; no numbers, body measurements, scores, tape instructions or body judgments in customer UI; no fake scans or measurements; no raw images, videos, segmentation masks or depth buffers saved/uploaded or committed; no unsupported garment-fit or physics claims. Keep failure/unknown states explicit.

At the end report file changes, Xcode build/test command + actual results (or say not run), real LiDAR iPhone validation steps, limitations and next dependency.

STORY ST-12 — Ben storefront adapter design, not live integration

Prerequisite: ST-07 CatalogRepository exists. Goal: prepare eventual retailer adoption while keeping the MVP mock-data-first.

1. Inspect how products, variants, finished-garment measurements, photos and 3D assets are represented in the catalog layer.
2. Define the future BenStoreCatalogAdapter interface, mapping shape, caching/error strategy and fields needed from Ben; keep auth tokens out of the repo.
3. Produce a concise owner question list: ecommerce platform, permitted catalog/API access, whether charts show garment dimensions or recommended body dimensions, exact garment-category coverage, product-photo rights and one or two sample SKU rows.
4. Document fallback for absent actual garment dimensions: display product appearance without a specific fit inference.
5. Implement a fake adapter test fixture if helpful; do not scrape live websites or connect external accounts without explicit permission.

Acceptance: adapter design and data checklist exist; no new production network dependency, no assumption that Ben's product feed/size chart is ready, no live integration claim.
```

## Stop/go protocol for the agent

After finishing each story, respond with: (1) actual changed files and PR link, (2) what works, (3) build/test output or precise reason unavailable, (4) what was checked on the physical LiDAR device, (5) known limitations and privacy status, (6) suggested next story. **Do not** mark a story done merely because code was written.

See [PRD](AVATAR_MVP_REQUIREMENTS.md), [architecture](AVATAR_MVP_ARCHITECTURE.md), and [backlog](AVATAR_MVP_STORIES.md).
