# FitCheck 2.0 — Avatar-first MVP product requirements

**Status:** proposed product specification for review; not a claim that features exist.  
**Target:** iPhone Pro with rear LiDAR for the first device-based prototype.  
**Source of truth for the customer flow:** create avatar/profile → save → choose an item → view estimated visual fit + clear fit descriptions.

## 1. Product objective

Help online shoppers understand how a specific garment *may* fit without requiring a tape measure, numeric body measurements, favorite-garment scan, size calculations or a manual scoring process. Eventually load products from Ben's online clothing store. The first MVP uses a small, openly labeled local product catalog.

**Core promise for MVP:** easy guided avatar creation, a reusable on-device profile, an interactive illustrative try-on, and honest garment-fit estimates where supported by scan and product information.

**Not yet a promise:** precise personalized body geometry, physically simulated fabric behavior, validated size predictions, guaranteed return-rate reduction, or a photorealistic body double.

## 2. Intended user journey

1. **First launch:** brief privacy and capability explanation, then primary button "Create my avatar." Do not force shopping before profile setup.
2. **Guided scan:** full-body front and side views using rear LiDAR and Apple Vision; a friend or stable camera mount may be needed. Text and simple progress graphics guide the customer. Automatic capture only when conditions pass; retry without requiring manual measurements.
3. **Profile ready:** display a rotatable *approximate* avatar if enough usable scan information exists. Store only minimum derived data needed to recreate it. If capture is inconclusive, show a retry state, not a made-up body.
4. **Shop:** browse sample items from a mock catalog. Only later replace with Ben's actual products.
5. **Try on:** choose an item and optionally a store variant when relevant. Render a preauthored garment representation on the approximate avatar.
6. **Fit feedback:** explain estimated garment fit in plain language by region (such as "Snug around the shoulders" or "Relaxed through the chest"), or "Fit can't be estimated yet" when data is insufficient. Clearly separate *visualization* from *fit confidence*.
7. **Revisit:** skip scanning if an avatar already exists. Allow rescan, remove profile, and view the data/privacy explanation at any time.

The app must be nonjudgmental about bodies. Evaluate clothing relative to customer preferences and available dimensions, not the customer's appearance.

## 3. Functional requirements

| ID | Requirement | MVP acceptance |
| --- | --- | --- |
| FR-01 | Avatar-first navigation | New customer lands on avatar creation; returning customer lands on saved avatar + "Explore clothing"; no product is required before a scan. |
| FR-02 | Hands-free capture interaction | No body measurement, tape, or manual point marking in the new flow; automatic front/side capture with retry and cancellation. |
| FR-03 | LiDAR support gate | On unsupported/denied camera access, show understandable recovery and no invented scan result. |
| FR-04 | Person detection & frame quality | Require a person substantially in view, reliable landmarks, aligned/valid depth, stable capture; reject inconclusive frames. |
| FR-05 | Internal geometry estimate | Derive only dimensions supported by the data; attach per-region origin, confidence and availability. Do not infer missing circumferences as facts. |
| FR-06 | Avatar mesh | Render a reusable, appropriately licensed 3D mesh; apply only supported proportions. Show illustrative status when personalization is incomplete. |
| FR-07 | Persistent profile | Save minimal derived geometry and avatar parameters on device; reopen without rescanning; include reset and permanent local delete. |
| FR-08 | Mock store catalog | Small T-shirt catalog with product ID/name/image, variants, garment measurement basis/provenance, and optional render asset; no real store API required. |
| FR-09 | Try-on visualization | Selected product appears as a simplified prepared garment on avatar; rotating and switching products works; not advertised as photorealistic drape. |
| FR-10 | Fit explanation | Convert checked internal geometry/garment ease to simple, neutral clothing-oriented descriptions; distinguish snug/regular/relaxed/unknown; no unvalidated "perfect fit." |
| FR-11 | Uncertainty handling | No recommendation/fit conclusion for untrusted scan or mismatched/unknown size-chart semantics; still allow illustrative preview if clearly labeled. |
| FR-12 | Zero-math customer UI | Never show body circumference, height, waist, centimeters, inches, raw score or confidence percentage to customer. Store-specific size labels may be visible only when required for product choice; no numeric scoring. |
| FR-13 | Privacy and consent | Explicit scan permission; on-device by default; no raw images/video uploaded or persistently stored; straightforward profile deletion; no sensitive test data in repo. |
| FR-14 | Accessibility and reliability | VoiceOver labels, readable text, accessible control alternatives to rotation, interruption/permission/retry states, and no blocking crash on missing depth. |
| FR-15 | Testability | Automated state/logic tests and a real iPhone Pro validation checklist; failures documented, not silently hidden. |

## 4. Design requirements

- Visually guided, friendly, uncomplicated interface. The UI should explain actions rather than expose numbers.
- Main navigation after setup: **My Avatar**, **Explore**, **Try On**. Profile/settings remains available without obstructing the journey.
- Camera copy: "Stand where your full body is visible"; "Turn sideways"; "Hold still"; "Try again"; "Camera unavailable." Avoid numeric countdowns, tape/circumference instructions and body judgments.
- Results copy: "Estimated fit preview"; garment-focused "Relaxed through the chest"; "Snug at the shoulders"; "Not enough information to estimate this area." No perfection/accuracy claims.
- Never generate body-evaluation or attractiveness ratings.
- A visual garment silhouette and a fit estimate are separate outputs. The visualization is not evidence that real fabric will drape identically.

## 5. Out of scope for two-week MVP

Live Ben-store connection; payment/checkout; shopping cart; production backend; arbitrary garment reconstruction from one photo; fabric simulation; self-serve single-phone rear-LiDAR scans; unsupported iPhones; on-device large vision-language/3D inference models; automated "guaranteed fit"; body shape ranking.

Build extension points for a retailer adapter but do not develop an unsupported store integration before learning Ben's platform and what his size charts contain.

## 6. Nonfunctional requirements and privacy

- **Local-first:** raw frames/depth/masks only during capture; dispose after processing; no upload, analytics payload, crash log or source-control artifact containing body images or body-derived measurements.
- **Minimum necessary data:** store avatar parameters, provenance, capture timestamp, source quality flags; do not retain raw recordings by default.
- **User control:** explicit start of camera scan, permission rationale, redo, delete, and clear instructions if no profile exists.
- **Performance:** scanning and rendering must not block the main UI thread; measure performance on the target iPhone before setting specific thresholds.
- **Versioned data:** persisted profile includes schemaVersion; data migration/fallback handles future updates.
- **Plain-language uncertainty:** if depth/person alignment cannot be verified, retry. If garment data are absent, do not fabricate fit feedback.
- **No made-up accuracy metrics:** define and collect tape/garment reference comparisons internally with consent, but don't claim validated accuracy without actual measurements.

## 7. Release success criteria

A fresh install on a **real** LiDAR iPhone Pro can complete the scan under documented conditions, derive a usable profile with explicit quality flags, recreate an approximate avatar after relaunch, browse a mock garment catalog, view a garment on the avatar, and read either supported fit feedback or an honest "unknown" message, all without manual measuring.

The team must demonstrate privacy behavior, pass compile/tests, and document which results are estimates and which are not yet validated.

## 8. Open decisions to resolve early

- Specific test iPhone Pro model and iOS/Xcode versions. Current README documents an iPhone 17 Pro Max but does not verify this new scanner.
- Who holds the rear camera during capture, or whether a stable mount is available.
- Whether Ben's size charts describe **finished garment measurements** or recommended body measurements. These are not interchangeable.
- Exactly which 1–3 T-shirts have authorized images, sample measurements and garment appearance assets.
- Which CC0 avatar mesh and compatible rig/garment assets work in RealityKit on device.
- What confidence/calibration tests justify showing specific per-region fit descriptions.

## 9. Evidence and current repo reality

On the default `main` branch, FitCheck has SwiftUI manual body/favorite/garment measurements, a depth-assisted manually marked scanner, a local profile store and an unvalidated scoring engine. Draft PR [#5](https://github.com/anshbalusa-ui/itchathon/pull/5) adds experimental auto-capture scaffolding but is not merged or verified on-device. **None of the avatar creation, saved avatar, mock shop or virtual try-on features above should be represented as already complete.**

See [engineering architecture](AVATAR_MVP_ARCHITECTURE.md), [story backlog](AVATAR_MVP_STORIES.md), and [coding-agent prompts](AVATAR_MVP_AGENT_PROMPTS.md).
