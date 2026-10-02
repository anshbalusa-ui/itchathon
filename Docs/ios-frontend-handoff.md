# FitCheck iOS handoff

## Integrated state

This GitHub checkout contains the current SwiftUI app. The guided front/side scene-depth scanner returns an editable partial body draft with estimated waist circumference, shoulder width, and torso length; chest circumference requires manual tape entry. Earlier owner-reported measurement quality predates removal of chest depth and does not validate the current scan. Garment ruler supports flat/hanging shirts and phone portrait/landscape; physical lifecycle behavior remains unverified.

The full iOS 27 simulator suite passed **46/46** on October 1, 2026 (45 unit tests and one UI test). See README for the test command.

Signed builds of this newer app were installed and launched on an iPhone 17 Pro Max (iOS 27.0) and an iPhone 17 Pro (iOS 26.6.2). The latter showed My Body with Scan Body available. A complete physical front/side scan, timed rehearsal, and tape comparison remain unverified.

## Next action: physical scanner probe

On the installed app:

1. Record or recover the known-tape **Probe** evidence: phone/OS, known span, projected span, absolute error, and whether overlay/tap alignment and boundaries were reliable. If no numeric log exists, repeat the probe and log it.
2. Record front/side body scan spans and corresponding tape measurements for waist width/depth, shoulders, and torso; enter chest circumference measured manually. Report generated outputs and per-dimension errors.
3. Record a repeated complete scan and per-dimension spread. Keep participant measurements private. If known-span or silhouette boundaries fail, report failure; never present manual values as scan proof or claim unlogged accuracy.

Complete scanner/tape evidence collection on the target demo iPhone. Two all-live body/favorite/candidate rehearsals in **3–5 minutes** remain open.

## Contract reminders

- Guided front/side depth capture uses operator-selected endpoints; no automatic Vision landmarks.
- Scan results remain an editable draft until explicit save.
- Results show the Body/Favorite selector and separate signed chest/shoulder/length scores (−100…+100), never an aggregate score. Physical checks gate size recommendations in the fit engine but are not displayed on the results screen.
- Size rows come from actual measurements; do not claim a “closest match” winner or invent adjacent sizes.
- No unquantified accuracy claims; no fabricated scan values or raw image persistence. Preserve owner-reported qualitative assessment separately from tape/error/repeat evidence.
