# FitCheck — Bitrig and coding-agent handoff

## Read first

1. [Approved specification](superpowers/specs/2026-09-27-fitcheck-ios-design.md).
2. [Implementation plan](superpowers/plans/2026-09-27-fitcheck-ios.md).
3. [Research, primary sources, and repository audit](superpowers/research/2026-09-27-fitcheck-feasibility.md).

This handoff supersedes the previous body-only product/0–100 scoring direction. It describes a target, not completed Swift work.

## Non-negotiable contract

- Preserve this native SwiftUI/ARKit app and `project.yml`; iOS 17+, Android out.
- Product loop: **body + known-good garment + candidate**.
- Guided body scan is required. Helper-selected front/side measurement locations are approved; no fully automatic landmarking requirement.
- Manual body/garment measurements are equal input paths; scan review/edit is mandatory.
- Save one body, one favorite, one candidate locally; no account/backend.
- Required garment dimensions: chest width, shoulders, length. Body: chest/waist circumference, shoulders, torso.
- Separate dimension Fit Scores: **−100 too small/short; 0 preferred target; +100 too big/long**.
- **No overall score or signed average.** Opposite errors cannot cancel. Physical body checks remain separate and authoritative.
- Scores use favorite-garment dimensions as zero. A contradictory reference or uncertain physical boundary requires review, not “perfect fit.”
- Compare real finished-garment size rows; never manufacture adjacent sizes or treat body-size ranges as item dimensions.
- Keep incomplete/unknown/incompatible sizes out of recommendations; nearest zero is better, not highest positive score.
- No raw image storage, upload, fake scan output, fabricated confidence, or borrowed accuracy claims.
- Bento is reference-only unless source permission is established.

## Existing source state

Baseline inspected: `d4313b3dda7c5fe179c9288295132458ddeb04b5`.

Keep the SwiftUI shell, models, local store, AR ruler, deterministic engine boundary, result/size views, tests, and XcodeGen.

Change these concrete gaps:

- Body scanner currently always throws unavailable.
- Body entry directly mutates saved state before Save; use drafts.
- Favorite garment and manual garment entry do not exist.
- Only body is persisted; candidate/chart state is transient.
- Existing engine scores body ease from 0–100 and selects maximum score. Replace semantics and every caller; no compatibility overload.
- Existing AR controller already has markers/reticle; add line, reset, pending save, interruption/permission handling, and safe field transitions.
- Existing ruler distances use plane raycasts, not direct depth samples. Do not reuse that measurement method for body silhouettes.
- Old tests include nonempty/fixture-wording checks. Replace with consumer-visible signed scoring, body constraints, invalid data, ranking, and persistence checks.

## Bitrig preflight and ownership

Bitrig/Xcode exist on the planning machine; XcodeGen was not on PATH. App build/device installation remain unverified.

```bash
brew install xcodegen
xcodegen generate
xcodebuild -list -project FitCheck.xcodeproj
xcrun simctl list devices available
xcrun devicectl list devices
```

Use actual simulator/device IDs in the plan's commands. Open this generated Xcode project in Bitrig, not a new project. Confirm developer team, camera permission, and runtime scene-depth support on both physical phones.

Two owners:

- **A / integration:** shared models/contracts, store, fit engine, manual entry, results, actual size rows, project configuration.
- **B / scanner:** body capture/depth geometry/device calibration, then ruler polish. Read frozen interfaces before starting; ask A before changing shared contracts.

Only A edits `project.yml` and integrates branches. Bitrig conversation branches must start from the same contract commit. Use device evidence, not simulator success, to accept sensor work.

## Live demo and stopping rules

User approved **3–5 minutes**, all measurements live, on team's iPhones. Both phones available; helper, consenting adult, close-fitting clothes, two standard T-shirts, tape measure available.

Record actual scan/tape differences and repeated-scan spread. A good-looking scan overlay is not measurement proof. Protect final rehearsal time; late scope reductions require explicit owner approval.

If scanner cannot return usable real measurements, report the observed failure and options. Do not declare manual-entry fallback to be a completed scanner. If local installation fails, resolve signing/device setup before visual polish.

The plan contains task contracts, concrete math/tests, Bitrig execution prompts, integration gates, and the acceptance matrix. Follow it rather than reviving obsolete body-only scoring or adding backend/ML/virtual try-on.
