# FitCheck — Commercial Product Delivery Plan

**Purpose:** Build a genuine customer-facing iOS product for an independent clothing retailer, not a hackathon demo.  
**Status:** planning and development criteria; nothing in this document asserts that new features have shipped.  
**Operating rule:** segment-by-segment development with measurable gates; do not race past unverified engineering or customer trust risks.

## Product contract

The customer creates a reusable avatar/profile **first**, then browses garments, views an illustrative garment on their avatar, and reads clear, clothing-focused estimated fit feedback **only where evidence supports it**. Customers do not measure themselves, enter body measurements, see body-size readouts, fit scores, percentages, or do calculations. Real product size labels may still be needed for selecting the purchasable variant. All numerical geometry/measurement logic, if justified, remains internal.

FitCheck is not permitted to equate a plausible 3D avatar with a validated garment fit, or to imply that LiDAR/Apple Vision automatically supplies accurate full-body circumferences or garment physics. Never describe a representation as the customer's exact body if insufficient evidence exists. The preview and fit-estimation subsystems carry independent verification states.

The business goal is improved customer clarity about garment fit, with a **hypothesis** that this could reduce size-related returns. Return reduction, shopper acceptance and prediction accuracy must be measured in a retailer pilot; no invented proof of ROI.

## Segment plan and gates

### Segment 0 — Baseline, contracts, privacy, feature isolation
**Outcome:** a dependable foundation for commercial development without destabilizing the working legacy app.

- Read and record actual main/PR #5/PR #6 status, repository architecture and test inventory.
- Run XcodeGen/Xcode on a Mac when available; preserve the baseline app and test scheme; record results honestly.
- Introduce **small, focused** versioned avatar-profile and journey contracts and deterministic unit tests.
- Isolate the new avatar-first experience behind a disabled-in-release development feature switch; no mock "success" or fabricated saved avatar.
- Decide minimum necessary data and local file-protection/deletion contract; do not persist raw camera/depth/masks.
- Document open questions for the retailer and support/permissions behavior.
- **Gate 0:** app builds and tests pass on actual supported Xcode environment; model/routing tests pass; no old-app regression or claim of avatar functionality. If no Xcode, mark branch **unverified** and do not approve gate.

### Segment 1 — Reliable guided LiDAR capture
**Outcome:** front and side camera evidence captured on a real LiDAR iPhone Pro without customer measuring.

- Review draft PR #5 rather than assuming it is complete. Fix lifecycle, concurrency, cancellation and iOS SDK issues.
- Handle permission denied, unsupported device, full-body framing, lighting, stable capture, clear guidance and retry.
- Align Vision person masks/landmarks with ARKit depth/confidence **on the person**, not merely with plausible scene-wide depth.
- Verify real front-vs-side evidence; refuse a scan when geometry/orientation/camera quality is insufficient.
- No user images, depth buffers or identifying video persisted or uploaded.
- **Gate 1:** actual device evidence in multiple ordinary settings, failed capture cases, cancellable/retry states, no leaked frame persistence. No numerical body-accuracy claim yet.

### Segment 2 — Reusable geometry and avatar
**Outcome:** a saved, rotatable, approximately personalized 3D avatar, with explicit unknowns.

- Build derived-geometry types with provenance, confidence/validation flags, missing-region handling.
- Validate repeatability against consented, independent physical references **internally** and record actual measurements/errors securely outside version control.
- Select and audit specifically licensed avatar base assets (e.g. CC0 core MakeHuman/MPFB assets, not casually downloaded third-party models); verify RealityKit import and any morph/scaling technique on device.
- Personalize only what the scan supports; visibly indicate if the result is illustrative rather than confirmed personalized.
- Save minimum derived profile locally, schema-version it, reload on cold launch, rescan and delete it.
- **Gate 2:** actual LiDAR-driven avatar rendering, documented limitations/repeatability, persistence and deletion demonstrated. Never mark generic fallback mesh as a verified personal reconstruction.

### Segment 3 — Catalog and garment visualization
**Outcome:** customer can browse a small, testable catalog and see a permitted, prepared T-shirt mesh on avatar.

- Define a replaceable repository interface. Start offline with clearly synthetic sample data and legally usable visuals, not fake live retailer products.
- Capture item IDs, garment category, variant, color, image rights, source/provenance, actual finished-garment measurements (if available), and rendering asset mapping.
- Prepare compatible top garment meshes/rig/coordinate conventions, avoid severe clipping, and handle missing asset without falsely simulating drape.
- **Gate 3:** on-device clothing selection and garment visualization work repeatedly after relaunch; missing data/assets degrade safely; no fabric/size-accuracy claims.

### Segment 4 — Fit interpretation and validation
**Outcome:** fit labels where supported, otherwise an explicit unknown state.

- Design fit engine accepting scan-derived geometry quality and *finished garment* size data, not a generic body-size chart treated as shirt dimensions.
- No favorite-shirt requirement; keep business logic independent from old hackathon signed-score UI.
- Produce neutral labels like "Closer at the shoulders," "Relaxed through the chest," "Can't estimate this area." No body ratings.
- Use controlled reference garments with permission and collect observed fit outcomes before claiming predictive accuracy. Avoid arbitrary universal thresholds.
- **Gate 4:** test matrix includes inconsistent/missing measurements, uncertain scans, different garments and size variants; outputs are appropriately unknown where not calibrated; claims reviewed against actual observations.

### Segment 5 — Real retailer pilot
**Outcome:** authorized store products, monitored pilot, privacy disclosure, support and realistic business feedback.

- Confirm Ben's ecommerce platform, data permissions, product IDs, real garment-measurement availability, inventory/variant conventions, legal product media rights and business ownership.
- Build a catalog adapter with least-privilege API access, no client-shipped secrets, rate limiting, caching and predictable failure behavior. Do not scrape or log into services without permission.
- Test with a small subset of real products; validate data accuracy and manual merchandising oversight before showing fitted recommendations.
- Establish opt-in, aggregated measures of scan completion, unavailable estimates, shopper comprehension, fit-feedback accuracy and any returns data, with appropriate privacy controls.
- **Gate 5:** actual retailer approval, authorized data, accurate catalog mapping, pilot support/contact path and no unsupported marketing statements.

### Segment 6 — Production release hardening
**Outcome:** controlled deployment, not merely a visually impressive demonstration.

- Test on supported iOS versions and physical devices; repeated camera sessions, low light, permissions, interrupted scans, background/foreground, memory, offline mode, app relaunch.
- Accessibility/VoiceOver, clear permissions, secure local storage and deletion, incident response, crash/error telemetry that excludes scan imagery and geometry, privacy policy/disclosures and App Store requirements.
- Verify dependencies/licenses, profiling/performance/battery, code signing, release builds, automated regression tests and staged TestFlight rollout; establish owner support and rollback plan.
- **Gate 6:** documented security/privacy and quality review, business sign-off, and fit-marketing claims supported by evidence. Full production release can take longer than the initial MVP timebox.

## Realistic schedule

The original two-week goal can target a **narrow functional feasibility prototype**, subject to working scanning hardware and approved assets. It is **not a reliable production-launch estimate**. Progress by gate, not by calendar pressure. Parallelize only independent work: 3D asset/license research and store product-data discovery can happen while scanning is validated. Don't integrate all subsystems in one enormous PR.

## Engineering quality requirements

1. **Correctness before appearance:** no placeholder or invented scan data presented as real; a beautiful shirt on a generic mesh is not evidence of physical fit.
2. **No regression:** preserve existing main flow until a thoroughly tested replacement exists. New customer experience is feature-flagged during construction.
3. **Source of truth:** `project.yml` (XcodeGen), SwiftUI, existing compatible frameworks; no unnecessary rewrite/backend.
4. **Quality evidence:** working code is not "done" until Xcode compiles, unit/UI tests run, actual LiDAR device validation is recorded, and limitations are documented. If tests cannot run in the coding-agent environment, report precisely what wasn't verified.
5. **Pull-request discipline:** small scoped changes, code review, no direct commits to `main`, no auto-merge, no unapproved external connections or data uploads.
6. **Privacy:** seek informed camera consent, prefer processing on device, never persist raw scans unless separately specified with consent and security review, and support profile deletion. Treat derived body information as sensitive.
7. **Business integrity:** label synthetic samples internally, respect image/model license and commercial-use terms, and do not assert product fit or return-rate benefit without evidence.
8. **User experience:** avoid numeric measurements/scores, body criticism, or fitness/body ideals; distinguish *garment behavior* and customer preference from judgments about the user.
9. **Accessibility:** understandable plain-language copy, screen-reader labels, loading/errors, no gesture-only controls.
10. **Observability without surveillance:** debug states may record error categories, never camera pixels, raw depth, full-body images or unique body measurements.

## Segment closeout template

Each PR closes with:
- Scope and user-facing change;
- Source file changes and dependencies;
- Actual Xcode build/test commands and results or blocked reason;
- Physical device model/iOS and test findings (no attached private scan images);
- Security/privacy and license checks;
- Failure behavior and confidence/unknown states;
- Explicit deferred work;
- **GO / NO-GO** for the next segment, backed by evidence.

## Current repository situation

- `main`: legacy measurement-based FitCheck; not yet avatar-first.
- [PR #5](https://github.com/anshbalusa-ui/itchathon/pull/5): draft experimental automatic scanner, not merged or proven on real hardware.
- [PR #6](https://github.com/anshbalusa-ui/itchathon/pull/6): draft requirements/architecture/stories/prompts; this production delivery plan lives on the same documentation branch.
- The existing story backlog `ST-00`–`ST-12` describes smaller implementation pieces nested within these commercial-grade segments.

Next: run the [production kickoff coding prompt](PRODUCTION_KICKOFF_PROMPT.md) to implement **Segment 0 only**.
