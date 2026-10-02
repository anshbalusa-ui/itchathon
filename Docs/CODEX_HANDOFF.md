# FitCheck handoff

## Current state

- GitHub `main` is the canonical SwiftUI/XcodeGen source; generate the ignored Xcode project from `project.yml`.
- Guided front/side scene-depth scan measures waist width/depth and returns an editable partial body draft with estimated waist circumference, shoulder width, and torso length. It does not measure chest circumference; manually measure and enter chest circumference before saving the body profile. Depth sensing remains required for 3D spans; a single width does not establish circumference.
- For physical comparison, double finished-garment flat chest width to approximate garment chest circumference. Double garment waist width only when measured at the navel-aligned waist. Do not treat raw flat width as circumference.
- The full iOS 27 simulator suite passed **46/46** on October 1, 2026 (45 unit tests and one UI test). See README for the reproducible command.
- Signed builds of this newer app were installed and launched on an iPhone 17 Pro Max (iOS 27.0) and an iPhone 17 Pro (iOS 26.6.2). The latter showed the My Body form with Scan Body available. Neither run verified a complete physical scan.
- Earlier owner-reported measurement quality is qualitative only; numeric tape spans, errors, repeat logs, and timed rehearsals remain unverified.
- GitHub `main` includes the guided scanner and fit UI. Continue work in this app rather than a replacement project.

## Next physical probe

On the installed app:

1. Record or recover the known-tape **Probe** evidence: phone/OS, known span, projected span, absolute error, and whether overlay/tap alignment and boundaries were reliable. If no numeric log exists, repeat the probe and log it.
2. Record front/side scan spans and corresponding tape measurements for waist width, waist depth, shoulders, and torso; manually measure chest circumference. Report generated outputs and per-dimension errors.
3. Record a repeated complete scan and per-dimension spread. Keep participant measurements private. If depth boundaries/alignment fail, report failure; do not substitute manual values or claim measured accuracy.

Collect scanner/tape evidence on the target demo iPhone. Two all-live body + favorite + candidate rehearsals in **3–5 minutes** remain open. Do not report unprovided numeric or timing evidence.

## Product invariants

- Body, favorite shirt, and candidate shirt inform separate signed chest, shoulder, and length scores (−100…+100); **never aggregate**. Results and size rows switch between Body and Favorite references with a top segmented control. Body chest compares doubled flat shirt width with body circumference using a 0.96 m scale (48 cm room ≈ +50); Favorite retains garment-to-garment scales.
- No disclaimer/physical-check card, measurement-source section, or limits prose on results. Physical checks still gate both size rankings; a favorite smaller than measured body never qualifies as a verified recommendation reference. Owner superseded original contradictory-favorite hard error while retaining signed comparisons.
- Body scan is guided front/side depth capture with operator-selected endpoints; automatic Vision landmarks are not part of implementation or acceptance.
- Garment ruler measurement is pending Use Measurement until explicitly accepted into editable draft. Do not imply ruler/device accuracy until physically checked.
- Size comparison uses actual entered garment measurements; no invented size grading or “closest match” contract.
- Never claim validated scan accuracy, probability, or fit guarantee. No fabricated values or raw-body-image persistence.

Keep changes in existing SwiftUI/XcodeGen app. Do not start a replacement project.
