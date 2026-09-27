# FitCheck iOS handoff

## Integrated state

Current Xcode work lives in this Bitrig `feat/ios-experience` checkout. Ansh's guided front/side scene-depth scanner is integrated and connected to the editable body draft. Current four-span scan returns waist circumference estimate, shoulder width and torso length; chest circumference requires manual tape entry. Owner reports earlier physical measurement quality on the connected iPhone as “pretty good”; this predates removal of chest depth and does not validate the new scan. Numeric tape spans, errors, and repeat logs were not supplied. Garment ruler supports flat/hanging shirts and phone portrait/landscape; physical lifecycle behavior remains unverified.

Earlier integrated simulator suite passed **42/42**. Current four-span scan and circumference-check unit suite passed **43/43**; full UI suite was not rerun:

```bash
xcodebuild -project FitCheck.xcodeproj -scheme FitCheck -configuration Debug -destination 'platform=iOS Simulator,id=BC1974AB-ED12-4805-8C3A-C5CF97D5616C' -derivedDataPath /tmp/fitcheck-simulator-derived -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 -only-testing:FitCheckTests CODE_SIGNING_ALLOWED=NO test -quiet
```

A signed build using `DEVELOPMENT_TEAM=T8U9HZY2S9 -allowProvisioningUpdates` was installed and launched on connected **iPhone 17 Pro Max, iOS 27.0**; screenshot showed FitCheck home with existing saved inputs. New four-span capture still needs a physical scan. Do not transfer the owner's earlier qualitative measurement assessment to this changed scan; timed rehearsal remains unverified.
An added unsupported-depth UI test was removed after simulator diagnostic timeouts. Unsupported-depth alert was observed on simulator, but no passing post-merge UI test is claimed.

GitHub PR #3 (`feat/ios-experience`) is Aashu's draft and owns Swift/Xcode integration/final review. PR #4 (`feat/body-scan`) is Ansh's draft; its scanner is integrated on this Bitrig branch. Keep drafts pending review and objective tape/repeat evidence.

## Next action: physical scanner probe

On the installed app:

1. Record or recover the known-tape **Probe** evidence: phone/OS, known span, projected span, absolute error, and whether overlay/tap alignment and boundaries were reliable. If no numeric log exists, repeat the probe and log it.
2. Record front/side body scan spans and corresponding tape measurements for waist width/depth, shoulders, and torso; enter chest circumference measured manually. Report generated outputs and per-dimension errors.
3. Record a repeated complete scan and per-dimension spread. Keep participant measurements private. If known-span or silhouette boundaries fail, report failure; never present manual values as scan proof or claim unlogged accuracy.

Complete scanner/tape evidence collection on connected **iPhone 17 Pro Max**. The approved plan originally expected iPhone 17 Pro and Pro Max; current owner narrowed device acceptance to this phone. Two all-live body/favorite/candidate rehearsals in **3–5 minutes** remain open.

## Contract reminders

- Guided front/side depth capture uses operator-selected endpoints; no automatic Vision landmarks.
- Scan results remain an editable draft until explicit save.
- Result shows physical checks and separate signed chest/shoulder/length scores (−100…+100), never an aggregate score.
- Size rows come from actual measurements; do not claim a “closest match” winner or invent adjacent sizes.
- No unquantified accuracy claims; no fabricated scan values or raw image persistence. Preserve owner-reported qualitative assessment separately from tape/error/repeat evidence.
