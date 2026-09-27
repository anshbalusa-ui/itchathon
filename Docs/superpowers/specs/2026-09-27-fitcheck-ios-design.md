# FitCheck iOS: product and engineering design

Status: architectural direction approved in conversation; written specification awaiting review.

## 1. Authority and confirmed decisions

This specification reconciles the supplied **FitCheck / ITCHATHON Product Context and Decisions** handoff with `anshbalusa-ui/itchathon` at commit `d4313b3dda7c5fe179c9288295132458ddeb04b5` and subsequent answers from the product owner. It supersedes the older body-only product direction in README and CODEX_HANDOFF. The source handoff remains authoritative where this specification does not explicitly record a later decision.

Confirmed directly:

- iOS only; Android is out of scope.
- Continue the existing native SwiftUI app, Swift fit engine, ARKit ruler, local storage, and XcodeGen configuration. No restart or Bento fork.
- Use Bitrig for development against the existing repository, not a separate generated app.
- Approximately **4 hours 15 minutes** of build time were available when planning began. This is a planning window, not a guaranteed delivery estimate; planning time consumes the same real deadline.
- Two builders and two physical devices: **iPhone 17 Pro and iPhone 17 Pro Max**.
- A helper may operate the rear camera. Operator-assisted measurement-location taps qualify as the required guided body scan. Fully automatic landmark extraction is not required.
- Body scanning remains required; manual entry is an equal input path, not a substitute for completing the scanner.
- A consenting adult, close-fitting clothing, two standard set-in-sleeve T-shirts, and a tape measure are available.
- All body and both garments' required dimensions must be measured live in the full demonstration.
- **3–5 minutes** is approved for that full live demonstration. The original 60–90 seconds applies only to the pitch summary, not the complete measurement flow.
- Distribution target: live demonstration on the team's own iPhones; no TestFlight or App Store submission requirement.
- Later scoring decision: **separate dimension Fit Scores from −100 to +100**, where negative means smaller/shorter than the user's preferred fit, positive means larger/longer, and zero means the preferred target subject to measured body constraints. **No averaged overall score.**
- Documentation-only delivery now. Implementing Swift code is a separate execution phase.

Exact device OS versions and signing readiness have not been established. They are executable preflight checks, not reasons to invent compatibility claims.

## 2. Product thesis, user, and promise

**My body establishes physical constraints. My favorite shirt establishes preference. A candidate shirt is checked against both.**

The initial user is a shopper frustrated by inconsistent size labels, with particular relevance to plus-size shoppers who cannot reliably try every product locally. The demo should show why a size label alone is insufficient without treating plus-size bodies as a uniform shape.

The useful answer is not just a number. It is: “This shirt has less chest room than your favorite, similar shoulders, and a longer body.” The score is an explainable comparison heuristic, **not** a probability, guarantee, medical measurement, or tailoring certification.

Success means a judge can identify the body constraint, the preference reference, the candidate, and the directional differences without an explanation of implementation internals.

### MVP scope

Required: guided body scan; manual body entry; scan review/edit; saved body profile; favorite-garment capture/manual entry; candidate capture/manual entry; chest/shoulder/length measurement; deterministic body-plus-preference fit; signed explanations; on-device persistence; actual-measurement size-chart entry and comparison; error/permission handling; a complete all-live demo.

Existing multi-size functionality is preserved and migrated to the new engine. Its polish and stage airtime are secondary, but source compatibility and the ability to enter actual size rows are not silently abandoned.

Excluded: Android, accounts, backend, cloud sync, OCR, retailer scraping/APIs, shopping checkout, billing, social features, full wardrobe, avatars, virtual try-on, ML fit prediction, automatic anatomical landmarking, pants/dresses, multiple preference profiles, scan history, and raw-body-image storage. No dependency is added for work Foundation/SwiftUI/ARKit already covers.

## 3. Research implications and alternatives

Evidence and source links: [research memo](../research/2026-09-27-fitcheck-feasibility.md).

| Approach | Product benefit | Cost/risk | Decision |
|---|---|---|---|
| Guided front/side depth scan with helper taps | Real on-device capture, explainable geometry, manual correction | Still needs surface selection, calibration, and device proof | Selected |
| Automatic pose + segmentation pipeline | Fewer helper interactions | Pose joints are not chest/waist boundaries; depth alignment and segmentation add failure modes | Not required for this deadline |
| Third-party body scanning SDK | Potential mature capture UX | Licensing, access, network/privacy, and integration not established | No new SDK dependency |
| Bento as app base | Related ruler/visual patterns | Existing FitCheck work would be displaced; no detected license; no body scanner | Reject fork/copy; reference only |

Public Apple APIs provide image/depth/pose primitives, not a ready-made clothing-fit body circumference measurement. Published results for other apps cannot be advertised as this prototype's accuracy.

## 4. Experience and state transitions

### Home

Three simple cards in existing NavigationStack:

1. **My Body** — missing / saved, source and last update.
2. **My Fit** — missing / favorite shirt name.
3. **Check a Garment** — primary action, with explicit guidance to complete missing prerequisites.

Do not obscure why an action is unavailable. Selecting a prerequisite should take the user directly to its creation flow. A complete report requires both a valid body and favorite. Candidate draft entry may occur before either prerequisite, but evaluation cannot.

### Body

`Choose Scan or Enter → capture or entry draft → Review Measurements → Save → Home`

- Scan screen explains helper use, rear camera, close-fitting clothing, front/side posture, and local-only processing.
- Front snapshot: chest width, waist width, shoulder width, torso length, each using two helper-selected endpoints.
- Side snapshot: chest depth and waist depth at the same anatomical levels.
- Chest and waist estimates are generated from front width and side depth; shoulders and torso are measured straight-line distances.
- Review shows all four values, units, and “Estimated from guided scan.” Edits change provenance to “Scan, edited.” Save is explicit.
- Cancel discards draft changes. Existing saved body must not be mutated through direct field bindings while editing.
- Denied permission, unsupported depth, invalid samples, interruption, and cancellation have distinct states. Provide retry and manual entry, never fabricated success.

### Favorite and candidate

`Choose Measure or Enter → named garment draft → chest / shoulders / length → Review → Save`

Use the existing GarmentProfile for both roles; do not duplicate fields into parallel favorite/candidate model hierarchies. A role enum selects destination and copy. One favorite and one candidate are saved.

The ruler retains center reticle, point A, point B, line, dimension label, and measured value. Completing B creates a pending measurement; **Use Measurement** commits it to the draft. Reset clears pending points/value. Switching dimensions resets A/B to prevent cross-dimension segments. A completed measurement does not overwrite saved data until the draft is saved.

For manual input, allow centimeters and inches, show unit beside every field, and normalize to meters once. Required fields cannot silently become zero after parse failure. Optional waist width may be blank, never interpreted as a measured zero.

### Result

Order: physical check → comparison with named favorite → three signed dimension Fit Scores and explanations → limitations. Each scale is labeled **−100 Too small / 0 Preferred fit / +100 Too big**; length uses **Too short / Preferred length / Too long**. Always print a plus sign for positive values. Do not put a standalone zero on screen without its dimension, reference, and physical-check context.

Chest detail shows body circumference, doubled favorite chest width, doubled candidate chest width, candidate-minus-body ease, and candidate-minus-favorite difference. Shoulder and length differences compare garments only. Never subtract body torso length from garment length and call it a like-for-like comparison.

Copy examples are generated from actual values, not pinned demo scores. “2 cm less chest room than Everyday Tee” is a circumference difference; “1 cm narrower laid flat” is a width difference. Label which one is shown.

### Size chart

A small form accepts product name, source, and rows of size label + chest width + shoulders + length + optional waist. Explicitly ask whether source values are **finished garment dimensions**. Body-size recommendation charts are rejected for this calculation with an explanation, not converted with invented ease.

Allow flat chest width or garment chest circumference as an explicit input interpretation; convert circumference to flat width exactly once before constructing existing size variants. Blank dimensions make that row incomplete. Do not invent neighboring sizes, and do not imply fixture data is a real retailer chart.

## 5. Measurement semantics and validation

Internal distances are finite `Double` meters. UI unit conversions are `cm / 100` and `inches * 0.0254`; storage/engine never change units with UI selection.

| Quantity | Definition | Use |
|---|---|---|
| Body chest circumference | Fullest chest level; front and side samples use same level | Physical chest check |
| Body waist circumference | Circumference at navel level for this protocol; label this explicitly | Optional physical waist check |
| Body shoulder width | Straight chord between outer shoulder landmarks | Stored and displayed; not a rigid-shirt impossibility rule |
| Body torso length | Front straight distance from suprasternal notch to navel level | Stored/displayed only |
| Garment chest width | Unstretched, laid-flat pit-to-pit width | Double once for approximate circumference |
| Garment shoulders | Seam-to-seam straight line for ordinary set-in sleeves | Preferred-fit similarity |
| Garment length | High shoulder point beside collar to bottom hem, same method for both shirts | Preferred-fit similarity |
| Garment waist width | Optional laid-flat width at corresponding worn navel level | Physical waist check only when alignment is explicitly known |

A generic retailer “waist” or hem width is not automatically at body navel level. Store optional alignment metadata; only compare waist physically when marked corresponding. Missing/misaligned waist produces “Waist not assessed.” No unmeasured abdomen, armhole, neck opening, sleeve, or stretch claim.

Body completeness: positive finite chest, waist, shoulders, torso. Garment completeness: positive finite chestFlat, shoulderWidth, length. Optional waist is zero-as-absent only at the legacy model boundary; new form uses blank-as-absent. Reject negatives, NaN, infinity, invalid numeric text, and implausible unit mistakes through review warnings rather than arbitrary body-size upper bounds. Do not reject legitimate large bodies because of narrow numeric assumptions.

Provenance is per dimension: manual, external, bodyScan, garmentScan, retailer; plus `wasEdited`. Legacy data without provenance displays “Source not recorded.” No fabricated confidence percentage. Depth sensor confidence is a capture-quality signal, not validated circumference accuracy.

## 6. Body scanner engineering contract

### Capture architecture

Keep BodyScanning as the capture/service boundary, but replace the zero-argument placeholder contract with explicit captured input. The scanner view/controller owns camera permission, ARSession lifetime, capture states, and helper interaction; pure geometry produces a draft BodyProfile from accepted metric spans. No ARKit dependency enters FitEngine.

Use `ARWorldTrackingConfiguration` with supported `.sceneDepth`, rear camera, and runtime capability checks. Do not use world-plane raycasts to measure a human silhouette. Do not run a competing AVCaptureSession alongside ARSession.

Keep at most two frozen RGB/depth snapshots in memory. Each snapshot owns a coherent image/depth/intrinsics/orientation/viewport-transform set from the same ARFrame. Freeze the displayed image and its corresponding depth together so taps cannot refer to a different frame. Release buffers on retake, save, cancellation, or background exit. Never serialize them or attach them to AI prompts/logs.

### Coordinate and sample rules

1. Normalize helper tap in the exact displayed viewport.
2. Invert that frame's ARKit display transform to obtain normalized camera-image coordinates. Account for aspect-fill crop and portrait orientation; do not apply an extra Vision-style vertical flip because this path does not use Vision coordinates.
3. Map image coordinates to the depth-map resolution. Scale focal lengths/principal point from camera image dimensions to depth dimensions.
4. Sample a bounded neighborhood, checking bytes-per-row and pixel format. Accept only finite positive depth with at least medium ARKit confidence; reject absent confidence for this guided measurement path.
5. Avoid averaging foreground body depth with background pixels. Use a coherent nearest foreground cluster; reject multi-cluster/edge ambiguity and require repositioning or recapture. Surface-boundary selection is a feasibility risk, not something unit tests can establish.
6. Back-project accepted pixels using camera intrinsics into one camera coordinate convention. A consistent camera-coordinate sign flip does not change pairwise distance; no world transform is required for endpoints in one frozen frame.
7. Compute each span from its two points within that same snapshot. Do not mix 3D points from front and side captures; combine only their scalar widths/depths.
8. Helper confirms levels, orientation, visible boundaries, and posture. Camera roll is coached; do not infer anatomical correctness from sensor confidence.

Shoulder and torso use 3D chord distances. Front torso spans estimate left-to-right diameter; side spans estimate front-to-back diameter at matching levels. Cloth, perspective, posture, depth edge artifacts, and non-elliptical shape all remain sources of error.

### Circumference estimate

For front width `w` and side depth `d`, let `a = w / 2`, `b = d / 2`, `h = ((a-b)/(a+b))²`:

`C ≈ π(a+b) × (1 + 3h / (10 + √(4−3h)))`

This is Ramanujan's ellipse approximation, not a claim that human cross-sections are ellipses. Equal diameters must reduce to `π × diameter`; swapping width and depth must not change circumference. Reject nonpositive/nonfinite inputs before geometry.

Retain separate named calibration multipliers for chest and waist, both initially 1.0. Change only from documented tape validation across repeated captures; never fit the system secretly to one desired score. Mark any empirical adjustment as demo-specific, not validated across users.

### Feasibility gate

The first scanner work must prove one frozen-frame depth-derived span on each available device against a known tape distance. Then complete one front/side body estimate. If coherent body boundary depth cannot be obtained, no later UI polish counts as scanner completion. Escalate with observed error and ask whether to revise deadline/method; manual entry must not be relabeled a completed body scan.

## 7. Fit engine design

### Minimal shared model

- Retain BodyProfile, GarmentProfile, MeasurementKey, GarmentSizeChart, and ProfileStore.
- Add optional provenance metadata to saved profiles with legacy-safe decoding.
- `ProfileStore.preferredGarment: GarmentProfile?` represents the one known-good garment. Separate conceptual role does not require a duplicate class.
- Replace FitReport's overall score/band with physical status and dimension results containing signed delta, signed score, and reference/candidate values. Each dimension score is in **−100...+100**; there is no aggregate Fit Score, physical score, or weighted preferred score.
- Invalid/incomplete input produces an explicit error rather than zero masquerading as a fit result.
- Evolve both `evaluate` and `evaluateSizes` to require the same preferred garment. Migrate every caller and relevant test; retain no body-only overload.

### Signed dimension heuristic

Use one small named configuration value, not a configuration service. Initial constants are engineering choices pending tape/device validation:

- Physical assessed dimensions: chest, plus waist only when corresponding waist measurements exist.
- Per-assessed-dimension ease: candidate circumference minus body circumference.
- Negative ease: “Smaller than measured body” under a no-stretch assumption. Not eligible for recommendation; positive shoulder/length scores cannot cancel it.
- Ease from 0 through 3 cm: “Close measurement — verify with tape.” This is a conservative **review band**, not an empirical confidence interval.
- Ease above 3 cm: passes that measured circumference check only when measurement quality supports it. Do not penalize additional room physically; signed preference scores expose excess room.
- Three always-visible scores: chest circumference, garment shoulder width, garment length. Optional aligned waist is a physical check, not a fourth preference score.
- For each dimension, `delta = candidate − favorite`; `score = round(clamp(100 × delta / scale, −100, +100))`.
- Initial scale distances for endpoint saturation are **12 cm chest circumference, 6 cm shoulders, 12 cm length**. Thus a candidate 6 cm smaller around the chest scores −50 for chest; 6 cm larger scores +50; an exact match scores 0. They are explicit prototype sensitivity choices, not population-derived sizing standards.
- Clamp only after preserving the unbounded normalized difference for ranking. A displayed +100 means “at least this far above target,” not a precise magnitude beyond saturation.
- Do not average signed values, compute a weighted total, convert them to a success percentage, or maximize positive scores.
- “Nearly identical” explanation deadband: 1 cm circumference; 0.5 cm shoulder/length. Keep the numerical score formula continuous apart from integer rounding; a score that rounds to zero is still an approximate match, not proof of exact equality.
- Mixed signs outside the explanation deadbands show **Mixed fit** plus all three rows. Example: chest −50, shoulders 0, length +50. There is deliberately no overall number.

A favorite shirt with measured chest circumference below the body's chest is a contradictory reference under the no-stretch model. Retain the saved data, explain possible stretch/measurement error, and require correction or verification before scoring against that reference. Do not silently redefine zero or claim that negative body ease is perfect. A reference in the 0–3 cm review band may produce directional comparisons, but neither zero nor any other dimension score licenses an overall “perfect fit” claim.

### Size recommendation without an aggregate score

Physical feasibility is the first gate. Recommend only rows that pass the measured checks. For eligible rows, minimize the **maximum absolute unbounded normalized dimension difference**; this internal minimax distance prevents opposing errors from cancelling and is never displayed as another Fit Score. Preserve input order in the list. If worst-dimension distances are within 0.02 (two score-point equivalents), show “Similar matches” and highlight the tied eligible rows without an invented winner. If no row passes, show “No verified match” or “None passes the measured checks,” depending on evidence. Unknown, incomplete, and incompatible rows are never promoted because their preference numbers happen to be near zero.

The result always states the coverage: “Chest checked” or “Chest and waist checked,” with “Shoulders and length compared with your favorite.” Existing “Won't Fit” certainty is replaced by measured-evidence language. Chest physical status remains visible beside its signed preference score; body shoulder and torso measurements are never substituted for garment target dimensions.

## 8. Persistence, lifecycle, and privacy

Keep UserDefaults + Codable for the small local records; do not introduce a database. Existing body key must decode without wiping saved data. Add separate favorite/candidate keys. Draft edits are local until save; show storage errors instead of silently succeeding.

After any saved body/favorite/candidate change, invalidate cached reports and size comparisons. Recompute from current saved inputs only. A change of body does not automatically change shirt dimensions or silently adapt a preference profile.

Provide a destructive-confirmation “Delete measurements” action that removes saved body/favorite/candidate/size chart data and clears in-memory reports. Do not claim app data is encrypted or excluded from OS backup unless those protections are implemented and verified.

The app makes no network request for measurement/fit. No account, raw-image upload, analytics, demographic inference, medical classification, or body-image persistence. Bitrig's developer build distribution is a separate data flow; its Remote deployment can upload signed app builds to Bitrig infrastructure. Do not equate that with uploading body scans. Keep real measurements/photos out of public fixtures, Git commits, screenshots submitted to coding agents, and crash logs.

Camera denied: explain Settings path and offer manual input without repeated permission prompts. Background/interruption: stop or pause session, discard unsafe pending capture, require deliberate resume/retake. Cancel/back releases camera. Garment and body capture never compete for the camera.

Accessibility basics remain required: Dynamic Type, 44-point touch targets, labeled controls, readable contrast, numeric results not conveyed solely by color, VoiceOver source/value/unit labels, and no forced animation.

## 9. Bitrig and collaboration

The current repository tracks `project.yml` and ignores generated `FitCheck.xcodeproj`. Local inspection found Xcode 27.0 and Bitrig installed, but `xcodegen` was not on PATH. No app build or hardware scan was performed during planning.

Keep XcodeGen as canonical configuration. Install/run it once in the execution preflight, generate project, then open the existing checkout/project in Bitrig. Public Bitrig docs confirm GitHub/Xcode-project support, not automatic bootstrapping of an XcodeGen-only repository. If Bitrig's repository picker requires a committed project, use its agent to generate from `project.yml` or open the locally generated project; do not quietly maintain two independent project configurations.

Do not raise the iOS 17 deployment target merely because development devices run newer iOS. Use the installed SDK with iOS 17-compatible APIs. Only one integration owner edits project.yml and shared models/store/engine contracts. Bitrig creates conversation branches; workers must start from the same contract commit, not unrelated generated apps.

Owner A: integration, models, persistence, fit engine, entry/results/size chart UI, final merge.
Owner B: body capture, depth math, scanner review integration, device measurement calibration; then ruler polish.
Both operators test the full integrated app on separate devices. Run no simultaneous changes to shared model contracts. Human teammate review is required at integration; no external council/independent-agent review has been claimed by this planning session.

## 10. Build sequence and honest schedule

Times are checkpoints from execution start, not elapsed-time claims or guarantees. Rebase this schedule on actual remaining time before starting.

| Window | Integration/product track | Scanner/device track | Gate |
|---|---|---|---|
| 0–20 min | Generate/build/install, freeze contracts | Sign/install second phone, camera/depth availability | Existing app launches on devices |
| 20–60 min | Manual body/favorite/candidate path + persistence | Frozen capture + metric span + front/side geometry | First real scan values, not fixtures |
| 60–130 min | Engine, result explanations, regression cases | Four-field body scan review, error states, ruler save/reset | Both independent paths functional |
| 130–185 min | Actual size-row entry, migrate comparison | Tape validation, capture UX and lifecycle | Integrated full loop |
| 185–225 min | Fix integrated failures, accessibility/source copy | Retest both phones, verify no raw-image persistence | Full all-live rehearsal |
| 225–255 min | Freeze build, docs/results, install final commit | Rehearse with same venue/setup; keep charged spare | 3–5 minute live flow twice |

Four-hour delivery is high risk because body-surface measurement is not implemented. Reserve the last 30 minutes for a known working build and rehearsal, not new features. If gates slip, do not silently delete body scanning, favorite-garment logic, or honest validation; obtain an explicit product decision.

## 11. Acceptance and release gates

### Automated behavioral checks

- Unit conversion and flat-width doubling happen exactly once.
- NaN/infinity/negative or missing required input cannot score.
- Favorite exact match yields zero signed deltas; changing favorite changes preference, not physical ease.
- Too-small chest cannot be recommended even with perfect shoulder and length scores; a contradictory favorite requires review rather than redefining zero.
- Exact preferred dimensions score 0; symmetric smaller/larger inputs score equal negative/positive values; endpoint saturation remains bounded; mixed signs are not aggregated.
- Optional waist has no invented measurement or claim; mismatched waist level is excluded.
- All-incompatible sizes produce no passing recommendation; ties remain honest; size labels do not affect scores.
- Ellipse symmetry, circle limit, nonfinite rejection, and known synthetic depth/intrinsics span.
- Legacy body data survives provenance additions; drafts cancel without mutation; changing inputs invalidates reports; deletion clears saved records.
- Depth/view mapping accounts for portrait transform, crop, bounds, missing confidence, buffer row stride, and invalid samples.

### Physical device evidence

Two repeated complete scans on each device using the same tape protocol. Suggested engineering acceptance gates: garment straight spans within 1.5 cm of tape; body shoulders/torso within 2 cm; chest/waist circumference within 5 cm; repeated circumference spread within 3 cm. These are **proposed release gates**, not achieved accuracy claims or statistical confidence bounds. Record actual errors, not just pass/fail. The 3 cm physical review band is not made valid by a 5 cm circumference error gate; scan-derived near-boundary recommendations require tape review, including when apparent ease is within the observed error envelope.

If measured scanner error exceeds a candidate's ease margin, physical status must request verification rather than assert compatibility; signed preference scores remain directional comparisons, not proof of feasibility. Before validation, scan-derived circumferences carry an unvalidated flag and require explicit review against tape before a positive physical claim. User edits alone are not evidence of accuracy.

Required device scenarios: deny camera; enter manually; grant camera and scan; cancel mid-scan; retake; invalid depth; background/foreground; save/relaunch; edit favorite/recompute; reset ruler mid-measurement; all-live flow; device switched; no network connectivity after installation.

Final stage rehearsal starts with no saved body/favorite/candidate. Complete four body dimensions and three dimensions for each garment, then fresh result, within approved 3–5 minutes, twice consecutively. Do not preload values or show a recorded capture as live. Tape corrections are allowed but must be visible and timed.

## 12. Demo script and honest language

- 0:00–0:20: problem and consent/setup; show empty profile state.
- 0:20–1:40: front/side capture, helper endpoints, review/save body.
- 1:40–2:40: measure chest/shoulders/length of favorite; name/save.
- 2:40–3:40: measure candidate's same dimensions; save and check.
- 3:40–4:30: explain physical chest evidence and three signed differences.
- 4:30–5:00: caveats/questions; size-chart feature only if time remains and values are clearly sourced.

This is a rehearsal allocation, not a demonstrated performance benchmark. A helper prepares shirts flat in advance without preloading measurements. State: “Guided scan estimates body measurements; you can review or enter measurements you trust. The fit score is a heuristic, and these dimensions cannot assess every aspect of fit.”

## 13. Specification self-review

- Body scan remains required and real; manual is equal input, not fake scanner fallback.
- Body + favorite + candidate all present; no obsolete body-only scoring path retained.
- Existing ruler/models/size feature preserved; no new app or backend.
- All-live measurement requirement retained; longer duration explicitly approved.
- No Bento code permission inferred from public repository visibility.
- Sensor confidence, repeatability, absolute accuracy, and score probability are distinct.
- Signed dimension scores replace the original 0–100 aggregate everywhere; zero is the preferred target subject to physical checks, not a missing-data default.
- iOS 17 app compatibility is distinct from Bitrig Remote's own OS requirements.
- Stored torso/body shoulder values are not conflated with garment length/seams.
- Optional waist limitations visible; cross-section level correspondence required.
- Real device feasibility, signing, actual timing, and accuracy remain unverified execution gates, not invented facts.
