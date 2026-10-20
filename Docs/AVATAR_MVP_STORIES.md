# FitCheck 2.0 — Prioritized development stories

**Planning status:** proposed stories ready for assignment. Only the experimental part of ST-00 exists in draft PR [#5](https://github.com/anshbalusa-ui/itchathon/pull/5). No story is considered tested or done from source-code existence alone.  
**Timebox:** two-week MVP attempt; adjust after first physical-iPhone feasibility tests.  
**Product order:** Create avatar → save profile → choose clothing → estimated avatar try-on + simple garment fit descriptions.

## Execution rules

1. Deliver each story on a separate branch/PR unless an active work-in-progress branch is explicitly selected. Do not silently merge, force-push, change unrelated code, or silently remove existing tests.
2. Read `Docs/AVATAR_MVP_REQUIREMENTS.md` and `Docs/AVATAR_MVP_ARCHITECTURE.md` first. Current `main` supports manual measurements; PR #5 adds unverified capture scaffolding.
3. Every story needs a runnable demonstration, a test plan, and explicit limitations. No Xcode build-success claims unless Xcode actually ran.
4. User never measures or enters body numbers. No numeric body measurements, fit scores, metrics or percentages appear in production UI.
5. Privacy by default: raw photos, depth/masks and videos are not persisted or uploaded. Do not commit real body scans or credentials.
6. Avatar appearance does not prove garment fit; return unknown for unsupported estimates and preserve honest demo labeling.

## Dependencies

```text
ST-00 Compile + validate experimental capture (PR #5)
    └── ST-01 Frame orientation/person-depth gating
         └── ST-02 Geometry extraction with uncertainty
              └───────────────┐
ST-03 Licensed avatar asset ── ST-04 Render avatar
                                    └── ST-05 Personalize avatar from reliable evidence
                                           └── ST-06 Save/load/delete avatar
ST-07 Mock product catalog ─────────────────────────┐
ST-03 Licensed garment template ─── ST-08 Render garment
ST-02 + ST-07 ──────────────────── ST-09 Fit estimates + copy
ST-06 + ST-07 + ST-08 + ST-09 ─── ST-10 Avatar-first UX
                                          └── ST-11 Real-device QA and demo
ST-12 Ben store adapter contract (design only) ─── future integration after Ben provides platform/data
```

Parallel streams: scanning/geometry (ST-00–02), avatars/3D assets (ST-03–05), catalog and future integration (ST-07/12), UX/QA (ST-06/08–11).

## Ordered story backlog

### ST-00 — Get scanner foundation building on a real iPhone
**Priority:** P0 · **Timebox:** Days 1–2 · **Depends:** draft PR #5; project/Xcode availability.  
**User story:** As a shopper, I can begin a guided avatar scan and get understandable camera guidance without measuring myself.

**Work:** Review PR #5, generate project from `project.yml`, compile, fix any Swift/Vision/ARKit errors, exercise permission and front/side capture on a LiDAR iPhone Pro; preserve manual demo on main.

**Acceptance:** real device builds and launches; no-camera and depth-unavailable states recover; front and side captures require actual person/stability; cancel/retake works; automated coordinator tests pass; no raw buffers saved. **Current status:** implementation draft exists, verification outstanding.

### ST-01 — Verify orientation and person-aligned depth
**Priority:** P0 · **Timebox:** Days 2–3 · **Depends:** ST-00.  
**User story:** As a shopper, I am not told the scan succeeded when the person was cropped, sideways at the wrong moment, or the depth didn't cover them.

**Work:** Establish image/depth orientation and resolution transforms; align masks to depth buffers; evaluate confidence *inside the person mask* and at landmarks; check front/side distinctness conservatively; make frame results cancel-safe.

**Acceptance:** unit tests for mappings and frame rejection; real device logs only non-sensitive diagnostic statuses; side-view pose occlusion handled; no scene-wide-depth-only acceptance; no fabricated orientation.

### ST-02 — Derive geometry, track missing information
**Priority:** P0 · **Timebox:** Days 3–5 · **Depends:** ST-01.  
**User story:** As a shopper, the app can build an approximate avatar using what was actually captured, without my entering body dimensions.

**Work:** Create a typed, in-memory, confidence-aware derived profile. Estimate only supported spans/shape parameters from calibrated person/depth geometry; run controlled repeated scans and independent references, internally.

**Acceptance:** deterministic tests for valid/invalid geometric inputs; incomplete data is `unavailable` not invented; no assumption that a flat width equals circumference; no numeric UI; validation limitations documented. **Fallback:** keep certain shape parameters unknown if evidence is weak.

### ST-03 — Choose and prepare legal avatar + shirt assets
**Priority:** P0 · **Timebox:** Days 1–4 (parallel) · **Depends:** Xcode renderer spike.  
**User story:** As a shopper, I can see a clear 3D avatar rather than a blank box.

**Work:** Evaluate MakeHuman/MPFB core CC0 assets and a compatible T-shirt; audit each selected asset license; export a low-weight renderable format; choose a compatible mesh/shape adjustment path; create asset manifest.

**Acceptance:** recorded asset provenance/license + sizes/formats; avatar and shirt load on actual iPhone with lighting/rotation; no AGPL/GPL application code embedded; do not assume arbitrary downloaded clothing assets are CC0. **Fallback:** a permitted generic prepared avatar/shirt.

### ST-04 — Implement interactive avatar viewer
**Priority:** P0 · **Timebox:** Days 4–6 · **Depends:** ST-03.  
**User story:** As a shopper, I can rotate and inspect my avatar smoothly.

**Work:** RealityKit or verified iOS 3D renderer; stable loading, no background data uploading, accessible rotation controls, empty/error states, lifecycle cleanup.

**Acceptance:** on-device rotatable avatar, tests for load/state behavior where possible, graceful missing asset fallback and documented render performance; no claim of scan personalization yet.

### ST-05 — Apply supported scan geometry to avatar
**Priority:** P0 · **Timebox:** Days 5–7 · **Depends:** ST-02, ST-04.  
**User story:** As a shopper, my avatar's supported proportions reflect the scan within the model's known limits.

**Work:** Map validated estimates into a small documented set of asset morph/scaling parameters; avoid distortions and unsupported dimensions; indicate when preview is illustrative.

**Acceptance:** synthetic test profiles visibly alter supported avatar parameters; unknown geometry never silently becomes invented values; real scan drive path verified; no claim of precise identity or body reconstruction. **Fallback:** illustrative avatar with clear copy.

### ST-06 — Keep and delete the avatar profile
**Priority:** P0 · **Timebox:** Days 6–8 · **Depends:** ST-05.  
**User story:** As a shopper, I create my avatar once, come back later without rescanning, and can delete it.

**Work:** Local versioned derived-data storage; migration behavior; saved-profile navigation; rescan and delete; memory/image cleanup.

**Acceptance:** cold launch retains avatar settings; deletion clears derived data and cached avatar changes; old manual profile unaffected while migrating; tests for bad versions and partial state.

### ST-07 — Build sample clothing catalog
**Priority:** P0 · **Timebox:** Days 4–6 (parallel) · **Depends:** product contract.  
**User story:** As a shopper with an avatar, I can select clothing from a few sample store items.

**Work:** typed catalog API, local mock records and source-of-truth garment size metadata; clearly distinguish synthetic developer test data from actual store measurements.

**Acceptance:** list/detail works offline; product/variant switching stable; missing/ambiguous chart data yields unknown fit; no dependency on Ben's website; no incorrect "real product" claims.

### ST-08 — Show garment on avatar
**Priority:** P0 · **Timebox:** Days 7–9 · **Depends:** ST-03, ST-04, ST-07.  
**User story:** As a shopper, I can see the chosen T-shirt rendered over the avatar.

**Work:** position/scale a compatible prebuilt shirt mesh, switch assets/colors, avoid clipping, and distinguish illustrative style from real fabric drape.

**Acceptance:** changing product updates shirt without changing body profile; real device demo shows interactive garment; missing 3D asset gives honest fallback; no fabric-physics claim.

### ST-09 — Conservative fit categories, not scores
**Priority:** P0 · **Timebox:** Days 7–10 · **Depends:** ST-02, ST-07.  
**User story:** As a shopper, I get plain-language clothing fit feedback when data supports it and honest uncertainty otherwise.

**Work:** new fit-estimation interface accepting profile provenance and finished-garment measurements; unit tests for snug/regular/relaxed/unknown pathways; neutral copy mapping; keep internal math hidden.

**Acceptance:** no favorite garment required in new flow; unsupported/uncalibrated checks return unknown; tests for missing, mismatched and inconsistent data; never expose score or cm/inch in shopper UI. **Fallback:** preview-only + clearly unavailable fit explanation.

### ST-10 — Wire the avatar-first experience
**Priority:** P0 · **Timebox:** Days 9–12 · **Depends:** ST-06–09.  
**User story:** As a first-time shopper, I see avatar setup before a product list; as a returning shopper, I go directly to saved avatar and browsing.

**Work:** onboarding, guided scan, profile-ready, explore, try-on, fit, retry, delete; remove numeric/manual paths from **new customer journey** without deleting old demo until replacement tested.

**Acceptance:** no manual measurement entry or scores anywhere in new UX; incomplete scans don't unlock confirmed avatars; cancellation/rescan safe; VoiceOver and empty states present.

### ST-11 — Physical test plan, release candidate and demo
**Priority:** P0 · **Timebox:** Days 11–14 · **Depends:** ST-00–10.  
**User story:** As the team presenting to Ben, we can honestly demonstrate a stable, repeatable end-to-end MVP.

**Work:** run existing/new tests; physical-device scenarios; inspect camera frame memory release; device rotation, permissions, failure handling, optional internal reference checks; prepare a demo script with limitations.

**Acceptance:** record command outputs and actual observed scan outcomes; no crash paths; on-device end-to-end demo from avatar creation through garment preview; disclose any illustrative/unknown fit areas; no claim of accuracy from a single anecdote.

### ST-12 — Define Ben store adapter without integrating
**Priority:** P1 design / P2 implementation · **Depends:** ST-07; access from Ben.  
**User story:** As the store owner, I can later supply product variants and actual garment measurements from my existing system rather than scanning stock again.

**Work:** adapter protocol, field mapping sample, identification of ecommerce platform and chart semantics, auth/data-permission plan, a dry-run with consented sample listings.

**Acceptance:** documented platform/data requirements and mock integration contract; no live scraping or unauthorized account access; no assumption that store size-chart numbers are finished-garment dimensions.

## Two-week sequencing

| Window | Primary target | Parallel track | Go/no-go gate |
| --- | --- | --- | --- |
| Days 1–2 | ST-00 hardware compile and scan | ST-03 asset selection | Camera + depth available on actual iPhone |
| Days 3–4 | ST-01 aligned/quality-gated capture | ST-03 mesh export, ST-07 mock catalog | Stable two-view evidence; valid asset license |
| Days 5–7 | ST-02 geometry and ST-05 personalization | ST-04 3D viewer | No fabricated measurements; 3D avatar renders |
| Days 8–10 | ST-06 storage, ST-08 shirt, ST-09 fit categories | ST-12 store-adapter design | Saved avatar and honest fit/unknown |
| Days 11–12 | ST-10 smooth user flow | ST-11 tests | Avatar-first journey complete |
| Days 13–14 | ST-11 device validation and Ben demo | Fix critical defects | Verified, limited MVP (or clearly labeled feasibility demo) |

**If geometry quality fails:** keep the scan/geometry task as research. Do not silently ship a generic avatar as personalized; either label it illustrative or defer that claim. **If fit inference fails:** ship the visual preview with honest "unknown" fit, not fabricated snug/relaxed labels. Both fallback modes should be communicated clearly to Ben.

## Definition of done for every story

- Branch/PR scoped to story, code reviewed, builds under Xcode (or explicitly marked unverified).
- Deterministic unit tests for logic and a relevant hardware/UI validation where applicable.
- Support/permission failure states; accessibility; no hidden numerical body UI.
- Updated docs/acceptance checklist; real-device evidence recorded without private scan imagery.
- No secrets, personally identifying body scans, raw camera frames, or dubious 3D asset licenses committed.
- No false fit-accuracy or retailer-integration claims.

For execution, use the paired prompts in [AVATAR_MVP_AGENT_PROMPTS.md](AVATAR_MVP_AGENT_PROMPTS.md). Start with **ST-00**, not with clothing physics or an AI-generated 3D mesh.
