# FitCheck handoff

## Current state

- This Bitrig `feat/ios-experience` checkout is source of current Xcode work.
- Guided front/side scene-depth scan measures waist width/depth and returns an editable partial body draft with estimated waist circumference, shoulder width, and torso length. It does not measure chest circumference; manually measure and enter chest circumference before saving the body profile. Depth sensing remains required for 3D spans; a single width does not establish circumference.
- For physical comparison, double finished-garment flat chest width to approximate garment chest circumference. Double garment waist width only when measured at the navel-aligned waist. Do not treat raw flat width as circumference.
- Before the latest scanner merge, the Apple Silicon iPhone 17 simulator suite passed **42/42, zero skipped**. With the chest-depth cutover, targeted unit tests passed **43/43**; full UI suite was not rerun:

```bash
xcodebuild -project FitCheck.xcodeproj -scheme FitCheck -configuration Debug -destination 'platform=iOS Simulator,id=BC1974AB-ED12-4805-8C3A-C5CF97D5616C' -derivedDataPath /tmp/fitcheck-simulator-derived -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 -only-testing:FitCheckTests CODE_SIGNING_ALLOWED=NO test -quiet
```

- Connected physical device: **iPhone 17 Pro Max, iOS 27.0**. Signed build succeeded with `DEVELOPMENT_TEAM=T8U9HZY2S9 -allowProvisioningUpdates`; app installed and launched, and screenshot showed My Fit form.
- Owner reports physical measurement quality on this iPhone is “pretty good” and says they would trust it. This is qualitative owner-reported acceptance only: numeric tape spans, errors, and repeat logs were not supplied; no quantified or population-accuracy claim is supported. Timed rehearsals remain unverified.
- Added unsupported-depth UI test was removed after simulator diagnostic timeouts; unsupported-depth alert was observed, but no passing post-merge UI run is claimed. Final installed build launched; latest screen capture showed phone's Face ID lock, not scanner interaction.
- GitHub PR #3 (`feat/ios-experience`) is Aashu's draft; Aashu owns Swift/Xcode integration and final review. PR #4 (`feat/body-scan`) is Ansh's draft; scanner implementation is integrated in this checkout. Keep both drafts pending review/device gate; coordinate further changes on this Bitrig branch, not a separate Xcode project.

## Next physical probe

On the installed app:

1. Record or recover the known-tape **Probe** evidence: phone/OS, known span, projected span, absolute error, and whether overlay/tap alignment and boundaries were reliable. If no numeric log exists, repeat the probe and log it.
2. Record front/side scan spans and corresponding tape measurements for waist width, waist depth, shoulders, and torso; manually measure chest circumference. Report generated outputs and per-dimension errors.
3. Record a repeated complete scan and per-dimension spread. Keep participant measurements private. If depth boundaries/alignment fail, report failure; do not substitute manual values or claim measured accuracy.

Complete scanner/tape evidence collection on the connected **iPhone 17 Pro Max**. The approved plan originally expected both iPhone 17 Pro and Pro Max; current owner narrowed device acceptance to the connected phone. Two all-live body + favorite + candidate rehearsals in **3–5 minutes** remain open. Do not report unprovided numeric or timing evidence.

## Product invariants

- Body, favorite shirt, and candidate shirt inform result. Report physical checks plus separate signed chest, shoulder, and length scores (−100…+100); **never aggregate**.
- Body scan is guided front/side depth capture with operator-selected endpoints; automatic Vision landmarks are not part of implementation or acceptance.
- Garment ruler measurement is pending Use Measurement until explicitly accepted into editable draft. Do not imply ruler/device accuracy until physically checked.
- Size comparison uses actual entered garment measurements; no invented size grading or “closest match” contract.
- Never claim validated scan accuracy, probability, or fit guarantee. No fabricated values or raw-body-image persistence.

Keep changes in existing SwiftUI/XcodeGen app. Do not start a replacement project.
