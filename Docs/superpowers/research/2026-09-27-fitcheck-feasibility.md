# FitCheck: feasibility and source audit

Research date: 2026-09-27. Scope: existing FitCheck app, Bitrig development, Bento reuse, on-device body/garment measurement, scoring semantics, privacy, and a two-person hackathon delivery. This is research and planning, not a device-validation report.

## Executive decisions

1. Build on FitCheck, not Bento. Existing code already has the architectural pieces worth retaining.
2. Bitrig's current Mac/Xcode workflow supports this native stack. Older interpreter-era Bitrig articles must not be mistaken for current framework restrictions.
3. Required body scan is the principal engineering risk. Guided helper-assisted depth capture is the approved approach; circumference is an estimate, not an Apple API output.
4. Measurements require explicit anatomical/garment definitions, provenance, units, and review. A size guide is not automatically a finished-garment chart.
5. The user revised scoring: separate signed chest, shoulder, and length scores in −100...+100, zero at preferred fit subject to body constraints. No averaged overall score or probability.
6. Prove the physical capture path first, in parallel with manual-input product flow. A simulator and a geometry unit test cannot establish sensor accuracy.

## 1. Repository evidence

Inspected `anshbalusa-ui/itchathon` main at `d4313b3dda7c5fe179c9288295132458ddeb04b5`. GitHub reports WRITE/push access. This planning checkout is separate from any teammate checkout.

| Evidence | Observed behavior | Consequence |
|---|---|---|
| [BodyScanService.swift](https://github.com/anshbalusa-ui/itchathon/blob/d4313b3dda7c5fe179c9288295132458ddeb04b5/Sources/BodyScan/BodyScanService.swift) | `GuidedBodyScanService.scan()` always throws unavailable | There is no working scanner to polish; implement actual acquisition and geometry |
| [ARMeasurementViewController.swift](https://github.com/anshbalusa-ui/itchathon/blob/d4313b3dda7c5fe179c9288295132458ddeb04b5/Sources/AR/ARMeasurementViewController.swift) | Scene depth/mesh enabled if supported; distance actually comes from plane raycast endpoints; markers and center reticle already exist | Preserve garment ruler; do not call it direct LiDAR body measurement; add line/reset/pending save |
| [ARMeasurementView.swift](https://github.com/anshbalusa-ui/itchathon/blob/d4313b3dda7c5fe179c9288295132458ddeb04b5/Sources/AR/ARMeasurementView.swift) | SwiftUI wrapper has empty update method | Add deliberate reset/field-transition contract and refreshed callbacks |
| [Models](https://github.com/anshbalusa-ui/itchathon/tree/d4313b3dda7c5fe179c9288295132458ddeb04b5/Sources/Models) | Meter doubles, flat chest/waist doubling, garment categories, size rows, no persisted provenance or preferred-garment role | Reuse fields; add minimal metadata and reference state; expose only T-shirt flow |
| [ProfileStore.swift](https://github.com/anshbalusa-ui/itchathon/blob/d4313b3dda7c5fe179c9288295132458ddeb04b5/Sources/Services/ProfileStore.swift) | Only body persisted; current garment and charts transient; errors discarded with try? | Persist favorite/candidate, preserve legacy body, surface save errors, invalidate stale reports |
| [BodyProfileView.swift](https://github.com/anshbalusa-ui/itchathon/blob/d4313b3dda7c5fe179c9288295132458ddeb04b5/Sources/Views/BodyProfileView.swift) | Direct bindings mutate saved state before explicit Save; centimeters only; no scanner action | Draft-based manual/scan review, cancel semantics, first-class scan entry |
| [GarmentScanView.swift](https://github.com/anshbalusa-ui/itchathon/blob/d4313b3dda7c5fe179c9288295132458ddeb04b5/Sources/Views/GarmentScanView.swift) | Always camera, no manual form, immediate callback assignment | Shared role-aware draft form; optional scanner sheet |
| [FitEngine.swift](https://github.com/anshbalusa-ui/itchathon/blob/d4313b3dda7c5fe179c9288295132458ddeb04b5/Sources/Services/FitEngine.swift) | Old body-only weighted 0–100 aggregate; no garment-length/preference comparison; size winner uses maximum score | Replace semantics and all callers; do not keep maximization for signed scores |
| [FitEngineTests.swift](https://github.com/anshbalusa-ui/itchathon/blob/d4313b3dda7c5fe179c9288295132458ddeb04b5/Tests/FitEngineTests.swift) | Four tests, including weak nonempty/positive checks and fixture-specific winning label | Replace incidental checks with signed behavior, constraints, ties, invalid data, real consumer invariants |
| [project.yml](https://github.com/anshbalusa-ui/itchathon/blob/d4313b3dda7c5fe179c9288295132458ddeb04b5/project.yml) and [.gitignore](https://github.com/anshbalusa-ui/itchathon/blob/d4313b3dda7c5fe179c9288295132458ddeb04b5/.gitignore) | XcodeGen; iOS 17; Swift 5.10; generated project ignored | Generate existing project; do not start a new Bitrig project or raise minimum OS by accident |
| README and CODEX_HANDOFF at same commit | Body-only thesis; automatic scanning optional; size matching elevated above revised live loop | Reconcile docs before implementation follows obsolete instructions |

Local facts observed: `/Applications/Bitrig.app` and `/Applications/Xcode.app` exist. `xcodebuild -version` returned Xcode 27.0, build 27A266a. `command -v xcodegen` returned no executable and exit status 1. This does not prove XcodeGen is absent from every possible installation path. No build, simulator launch, code-signing test, or hardware capture was performed during research.

## 2. Bitrig: current capabilities and integration risk

Primary sources:

- [Existing GitHub/Xcode projects](https://bitrig.com/blog/bitrig-works-with-xcode-projects-from-github): imports repositories, builds existing schemes/targets, edits across files, and creates branches for conversations with GitHub sync/PR support.
- [Bitrig Remote](https://bitrig.com/remote): full Xcode toolchain and Apple SDKs; Remote connects to a powered-on Mac; Remote requires iOS 26 and Pro for its device-install/distribution flow. This is not FitCheck's minimum OS.
- [Device installation](https://bitrig.com/blog/bitrig-remote-install-and-distribute-apps): “Install on this iPhone” compiles/signs on Mac and uploads a build to Bitrig's server for installation. Native installation matters because camera/depth cannot be validated through a streamed simulator.
- [Plan modes and skills](https://bitrig.com/blog/plan-steer-and-dictate): supports plan mode, steering, reusable skills, and agent workflows. A checked-in Superpowers plan can be used as an execution contract; availability of any particular skill still depends on the selected agent.
- [Current product page](https://bitrig.com/): native Swift, full projects, macOS 15+/Apple silicon requirement, GitHub support.

Implications:

- Prefer the current Mac/native toolchain path, not obsolete assumptions about Bitrig's initial Swift interpreter.
- The public documentation does not explicitly guarantee automatic `project.yml` → XcodeGen project generation. Preflight must generate and open the existing project and verify the scheme/test target.
- No arbitrary paid service or backend is required for runtime. Bitrig's own subscription/signing setup is development tooling, not product infrastructure.
- Remote's streamed UI can review manual forms/results, but actual iPhone runtime must prove body scan, garment ruler, permissions, interruption, and performance.
- Avoid real body images in Bitrig prompts/simulator screenshots sent to agents. The intended app privacy boundary is local processing; development-tool upload paths require separate care.

## 3. Bento: specific reuse assessment

Inspected public [Bento repository](https://github.com/cijjas/bento), its README, and [ARMeasureViewController.swift](https://github.com/cijjas/bento/blob/main/Sources/AR/ARMeasureViewController.swift). GitHub repository metadata returned `license: null`; listed root files did not include a license, and README did not grant one.

| Area | Relevant lesson | FitCheck action |
|---|---|---|
| AR ruler | SceneKit points/line, live preview callback, reset, camera coaching, SwiftUI wrapper | Implement the small missing behaviors in FitCheck's existing controller using Apple APIs |
| Geometry helper | Euclidean segment distance and scene line orientation | Existing simd/SceneKit APIs already sufficient; do not add helper library for distance |
| Profiles / fit evaluator | Capture data separated from pure fit logic | Existing FitCheck architecture already does this |
| Garment diagrams | Measurement instructions can reduce user ambiguity | Use simple native instruction text/diagram if useful; do not copy assets/code without permission |
| Sharing / .bento cards | Portable measurements | Out of scope; no importer/exporter needed |
| RoomPlan, object capture, ghost boxes | Furniture/object use cases | Out of scope; not a human circumference solution |

Bento README states its AR/RealityKit sources had not been built against the iOS SDK. Its 1–3% accuracy language is a repository claim, not FitCheck evidence. Neither should be promoted into our release criteria.

[GitHub's licensing guidance](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository) states that absent a license, ordinary copyright restrictions remain. Public viewing/forking permissions do not establish general permission to redistribute derivatives. Decision: reference architecture only. If author later grants a suitable license/permission, reevaluate individual small components, not a wholesale fork. This is a practical dependency decision, not legal advice.

## 4. Apple APIs: what they do and do not establish

### Depth acquisition and coordinate conversion

[Apple's scene-depth point-cloud sample](https://developer.apple.com/documentation/arkit/displaying-a-point-cloud-using-scene-depth) explicitly requires LiDAR scene-depth support, checks runtime capabilities, enables frame semantics, and uses depth texture plus camera intrinsics to produce 3D points. This is the appropriate primitive for direct depth-derived spans.

[ARDepthData confidenceMap](https://developer.apple.com/documentation/arkit/ardepthdata/confidencemap) documents per-depth-sample confidence and sensitivity to environmental light, reflective surfaces, and light-absorbing surfaces. This is not a probability that chest circumference is correct.

Engineering inference: frozen RGB/depth/intrinsics from one frame avoids temporal mismatch when a helper selects endpoints. Portrait viewport crop and camera-image/depth-resolution conversion must be verified numerically and on-device. Human silhouette boundary pixels may mix background and body; enabling LiDAR does not solve anatomical landmark selection.

### Vision is not a body tape measure

[WWDC23: 3D body pose and person segmentation](https://developer.apple.com/videos/play/wwdc2023/111241/) explains:

- 3D pose returns 17 skeletal joints relative to a hip-root origin.
- Depending on available depth metadata, body height can be measured or a reference **1.8 m**.
- Person segmentation supplies masks, not chest/waist circumferences.
- Vision's depth-enabled request handler uses AVDepthData; ARKit's ARDepthData is not the same type. Do not assume they are interchangeable.

Therefore: shoulder joints are not guaranteed outer garment-shoulder landmarks; pose alone must not generate absolute chest circumference. The approved manual-helper selection removes automatic landmarking from the critical path without replacing capture with manually typed centimeter values.

### Geometry limitations

Front/side ellipse geometry is an interpretable approximation. Human chest and waist cross-sections are not perfect ellipses; breasts, abdominal shape, clothing, posture, breathing, and mismatched measurement levels can dominate sensor precision. Front width plus side depth must represent the same anatomical cross-section. Surface chord distances do not directly equal tape circumference.

Do not use rigid plane raycasts for the body. Existing garment plane raycasts are useful for flat shirts on a stable surface, with their own error checks.

## 5. Empirical evidence: repeatability is not accuracy

Primary study read: Graybeal, Brandner, and Tinsley, [Evaluation of automated anthropometrics produced by smartphone-based machine learning](https://pmc.ncbi.nlm.nih.gov/articles/PMC10442791/), British Journal of Nutrition, 2023, DOI 10.1017/S0007114523000090.

Study: 115 adults, two applications, repeated smartphone/tape measures under a controlled protocol. Participants wore minimal form-fitting clothing; front/side capture used a standardized camera setup. Measurement site definitions were explicitly important.

Important distinction:

- Reported repeatability was high; waist/hip precision errors were roughly 0.5–1.9 cm.
- Waist RMSE versus tape was roughly 5.2–6.5 cm, and individual agreement limits were wider.
- Small mean bias or high correlation does not guarantee an individual shopper's measurement is accurate enough to discriminate neighboring shirt sizes.

Transfer limit: those are results for other applications and study protocols, not the proposed LiDAR/ellipse implementation. They support repeated tape checks and cautious claims, not a borrowed accuracy promise. The population/protocol also does not establish inclusive validation across all body shapes, accessibility conditions, clothing, or environments.

Planning consequence: show scan estimates as estimates; record absolute error and repeatability separately; use tape review when the measurement error envelope overlaps the physical-fit boundary. Do not show “high confidence” from a sensor confidence map alone.

## 6. Measurement-input semantics

Primary retailer search located [UNIQLO How to Measure](https://faq-us.uniqlo.com/articles/en_US/FAQ/How-to-Measure); direct page fetch returned HTTP 403. Search results distinguish body from product measurements, but the inaccessible article is not treated as a fully inspected source. No retailer chart was downloaded or approved as real demo data.

The product distinction follows directly from its data model: body-size ranges identify the person a retailer intends to dress; finished-garment dimensions describe the item. There is no valid generic conversion without design-specific ease/construction data. Plan therefore requires explicit chart kind and rejects body-size ranges for garment comparison. Flat width and full circumference must also be distinct input choices.

The supplied product examples and existing `Demo Brand` chart are synthetic fixtures. They may be used in tests or clearly labeled developer demos, not represented as measured merchandise or retailer evidence.

## 7. Blind spots resolved with owner

| Question | Owner answer | Architectural effect |
|---|---|---|
| Device | iPhone 17 Pro + Pro Max | LiDAR-capable path, still runtime-check support |
| Operator | Helper acceptable | Rear-camera front/side acquisition |
| Time | 4h15m at planning start | Early feasibility gate, two tracks, no automatic landmark requirement |
| Team | Two builders/two devices | Separate scanner and integration ownership |
| Distribution | Own-device live demo | No TestFlight review/store readiness critical path |
| Body scan definition | Guided helper taps acceptable | Real depth spans and ellipse estimates; no automatic CV requirement |
| Demo | Everything measured live | No preloaded favorite/body as acceptance shortcut |
| Duration conflict | 3–5 minutes accepted | Original 60–90 sec is pitch only |
| Setup | Consenting adult, close-fitting clothes, two tees, tape available | Controlled validation possible |
| Score | Signed −100...+100, 0 ideal | Remove old score aggregate/maximization |
| Perfect relative to what | Preferred fit, constrained by body | Reference garment sets dimension zero |
| Mixed fit | Always separate dimension scores | No opposite-sign cancellation or overall scalar |

## 8. Remaining verification, not hidden assumptions

- Actual iOS versions, developer signing, app installation and scene-depth capabilities on both phones.
- XcodeGen bootstrap within chosen Bitrig workflow.
- Correct image/depth/viewport coordinate mapping and coherent silhouette depth samples.
- Four body dimensions from real captures, tape error and repeated-scan spread.
- Whether all-live flow finishes inside five minutes after repeated rehearsal.
- Whether garment waist data corresponds to the body measurement level; absent this, no waist claim.
- Real retailer measurements for optional size-chart demonstration; no inference from labels.
- Legal permission if any Bento source reuse is later requested.

No physical-device, build, accuracy, usability, or independent-review success is claimed by this memo. The design specifies gates to establish those facts during execution.
