# itchathon — FitCheck iOS

**My body + my favorite shirt + a shirt I want → how will it fit?**

FitCheck is a native iOS hackathon prototype for shoppers underserved by inconsistent clothing sizes. Body measurements provide physical constraints; a known-good shirt captures preferred fit; candidate dimensions reveal what will feel tighter, looser, shorter, or longer.

## Approved product direction

1. **My Body:** guided helper-operated front/side depth scan, or equally prominent manual entry. Review/edit chest, waist, shoulders, and torso before saving.
2. **My Fit:** measure or enter a favorite T-shirt's chest width, shoulders, and length.
3. **Check a Garment:** measure or enter the same dimensions for a candidate.
4. **Results:** separate signed Fit Scores for chest, shoulders, and length:
   - **−100:** much smaller/shorter than preferred.
   - **0:** preferred fit, subject to measured body constraints.
   - **+100:** much larger/longer than preferred.
   - **No averaged overall score.** Tight chest and excessive length must not cancel into “perfect.”
5. **Compare sizes:** evaluate actual finished-garment dimensions against the same body and favorite. Recommend physically viable options nearest the preferred dimensions, not the largest positive score.

Scores are prototype heuristics, not fit probabilities or guarantees. Missing waist dimensions mean waist is not assessed. A retailer's body-size guide is not a finished-garment measurement chart.

## Current implementation versus target

This documentation update does **not** implement the approved behavior.

Existing code includes the SwiftUI shell, body persistence, a plane-raycast garment ruler, body-only fit engine, size comparison, and basic tests. `GuidedBodyScanService.scan()` still throws unavailable. The favorite-garment flow, working body scanner, signed dimension scores, richer persistence, and revised UI remain implementation tasks.

Do not use the current engine's 0–100 aggregate as the new scoring contract.

## Execution documents

- [Approved product/engineering specification](Docs/superpowers/specs/2026-09-27-fitcheck-ios-design.md)
- [Primary-source research and feasibility audit](Docs/superpowers/research/2026-09-27-fitcheck-feasibility.md)
- [Superpowers implementation plan](Docs/superpowers/plans/2026-09-27-fitcheck-ios.md)
- [Agent/Bitrig handoff](Docs/CODEX_HANDOFF.md)

Read the spec and plan together. Later confirmed decisions in these documents supersede the original body-only handoff.

## Stack and setup

- SwiftUI, native iOS **17+**, existing XcodeGen project.
- ARKit direct depth for the planned body scanner; existing ARKit raycasts for flat garments.
- Pure Swift fit logic, local measurements, no required backend/account.
- Bitrig against this repository; do not generate a separate replacement app.

```bash
brew install xcodegen
xcodegen generate
open FitCheck.xcodeproj
```

Use an installed Xcode version supporting the device OS. Open the generated existing project in Bitrig, or have its repository agent run XcodeGen. `project.yml` remains canonical; generated `FitCheck.xcodeproj` is ignored. Bitrig's public docs do not establish automatic XcodeGen-only repository bootstrap.

Simulator proves forms and deterministic logic, not body/garment measurements. Sign and install the actual app on both demo phones early.

## Hackathon boundaries

- Two builders; iPhone 17 Pro and Pro Max available.
- Approximately 4h15m build window was reported at planning start; recheck remaining time before execution.
- Required **3–5 minute all-live** demo: body, favorite, candidate, fresh result. The 60–90 second target is pitch summary only.
- Helper-assisted body scan approved; close-fitting clothing and tape validation available.
- Tops/T-shirts only; manual/external measurements are first-class.
- No Android, auth/backend, retailer APIs/OCR/scraping, virtual try-on, avatars, ML scoring, or wardrobe expansion.
- No raw body images persisted or uploaded by the app. Keep real participant data out of the public repo and coding-agent prompts.

Body scanning remains required. A manual-only app is not completion of this plan.

## Bento reference

[Bento](https://github.com/cijjas/bento) is an architectural reference for native measurement UX, not a dependency or replacement codebase. No license was detected during research. Do not copy or redistribute its code without an appropriate grant of permission.

## Verification status

Planning checked source, public documentation, local tooling, document links, and proposed mathematical examples. It did not build the app, validate signing, run a physical scan, or establish measurement accuracy. The implementation plan requires those checks before claiming completion.
