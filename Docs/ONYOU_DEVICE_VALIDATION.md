# On You — device validation

## Evidence boundary and current result

**All physical body and shirt cases in this document are NOT RUN.** The fresh `devicectl` / `xctrace` inventory found no usable physical iPhone; the paired phone was unavailable/offline. Raw device identifiers remain in the external evidence directory, not this repository. No physical test assets can be positioned or observed through the available tooling. No user is being asked to supply scans or perform tests.

PR #27 (`f84435a307922aab8e27eab47b27cfd90b58c9d7`) is the starting implementation, not a new scanner. Native capture, photogrammetry, depth admission, local storage and garment inference already exist. Simulator rendering, authored depth/mesh fixtures and a licensed model-conversion photo are **software evidence**, not physical capture or dimensional ground truth. Current/final software results belong in [release readiness](ONYOU_FINAL_RELEASE_READINESS.md).

Local workflow verification also passed an unsigned `iphoneos` Debug build with the per-command validation bundle override. Generated metadata was inspected: bundle `app.bitrig.new.0bab6520-e754-44f9-acd8-d1ecceeda6e3.validation`, display name **On You**, minimum OS **26.0**. This proves the isolated build recipe, not signing, installation, camera capture or physical accuracy; those remain NOT RUN.

A stationary nonpersonal mannequin and independently measured rigid targets can exercise capture mechanics. They cannot establish human motion tolerance, hidden anatomy, face likeness or real-person reconstruction accuracy. If the native SDK cannot select the nonpersonal target, record an asset limitation; do not substitute private body scans or weaken admission.

## Prerequisites and data isolation

- iPhone application, minimum iOS **26.0** (`Project.json`); body capture requires both `ObjectCaptureSession.isSupported` and `PhotogrammetrySession.isSupported`. Shirt measurement requires supported AR world tracking/scene depth and camera permission. Do not infer support from a model name alone.
- Authorized, connected, unlocked test phone with Developer Mode, an already authorized development signing identity/profile and sufficient storage. No production credentials/profiles are changed by this work.
- Use a separate **validation bundle identifier/sandbox**, not an installation over an existing personal On You app. Do not erase a phone, clear another app's data, uninstall an existing app or reset privacy globally.
- Nonpersonal stationary full-height mannequin, matte/texture-rich calibration objects, a safe unobstructed walking area, even lighting, ordinary short-sleeved test shirts, contrasting horizontal surface and independent measuring equipment. Record reference dimensions only when actually measured; no retailer dimensions or generated values as truth.
- Keep any necessary nonpersonal images, models, reference dimensions and raw diagnostics in a controlled local validation directory. The native pipeline necessarily captures temporary photos; do not export personal images/depth or commit captures/device identifiers. Existing cleanup attempts to remove temporary inputs after successful preparation or cancellation; verify actual removal and abandoned-attempt recovery under device lock and I/O failures. Nonpersonal reference measurements are permitted and necessary for later accuracy studies.

## Reproducible operator workflow

These are procedures for a **future authorized validation operator**, not claims that a device run occurred. The CLI installation/launch interfaces were checked with the installed toolchain. A signed installation, native capture and every physical outcome remain NOT RUN.

### 1. Discover and build without changing repository identity

```sh
xcrun devicectl list devices --json-output "$OUT/devices.json"
xcrun xctrace list devices
xcodegen generate --spec Project.json

VALIDATION_ID=app.bitrig.new.0bab6520-e754-44f9-acd8-d1ecceeda6e3.validation
xcodebuild -project 'On You.xcodeproj' -scheme FitCheck -configuration Debug \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath "$OUT/UnsignedDevice" CODE_SIGNING_ALLOWED=NO \
  PRODUCT_BUNDLE_IDENTIFIER="$VALIDATION_ID" build
```

`OUT` is a new protected local evidence directory outside Git. The unsigned build checks software/SDK compatibility only and cannot be installed as a physical test app. It is not a camera test. The customer-facing product remains **On You**; `FitCheck` is only the module/scheme.

### 2. Authorized signing, installation and launch

Only after a suitable phone, approved nonpersonal assets and an existing authorized profile are available, set `DEVICE_UDID` and `AUTHORIZED_TEAM` from that authorized environment. Do not create/change production credentials or use automatic provisioning-update flags. If authorization/profile is missing, record BLOCKED rather than installing over another app.

```sh
xcodebuild -project 'On You.xcodeproj' -scheme FitCheck -configuration Debug \
  -destination "platform=iOS,id=$DEVICE_UDID" -derivedDataPath "$OUT/SignedDevice" \
  PRODUCT_BUNDLE_IDENTIFIER="$VALIDATION_ID" DEVELOPMENT_TEAM="$AUTHORIZED_TEAM" \
  CODE_SIGN_IDENTITY='Apple Development' build
APP="$OUT/SignedDevice/Build/Products/Debug-iphoneos/On You.app"
/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Info.plist"
codesign --verify --deep --strict "$APP"
xcrun devicectl device install app --device "$DEVICE_UDID" "$APP"
xcrun devicectl device process launch --device "$DEVICE_UDID" \
  --terminate-existing "$VALIDATION_ID"
```

Check the printed identifier is the validation ID before installation. Launch with **no** `-onyou-tryon-fixture`, `-onyou-fixture-*` or `-fitcheck-*` arguments: those are not physical capture evidence. `--console`, if used, attaches standard streams; it does not by itself guarantee collection of OSLog info events.

### 3. Observe existing instrumentation

- In Console.app select the authorized phone, filter subsystem `app.onyou`, category `BodyScanTiming`, and enable Info messages. Existing `BodyCaptureModel` also logs abstract state/pass/shot transitions. Record stage durations, outcomes and rejection reasons, not identifying file paths or personal media.
- Body timings already distinguish framing, selection, body pass, checkpoint, detail pass, finalization, photo preflight, native reconstruction, texture validation and avatar loading. Native model-request progress/ETA is Apple's output; a spinner is not a completed reconstruction.
- Shirt live guidance exposes recognition/stability and per-frame foreground/outline/landmark/depth/projection/total durations plus model prediction time. These are transient diagnostics, not a retained accuracy report. Separately time camera-entry → reviewable result and retries; do not equate one inference duration with end-to-end capture time.
- Record app commit, build configuration, device model, OS/SDK, fixture code, actual conditions, run number, stage/result and reference method. Use anonymized fixture codes, not personal names/device identifiers. A failure or unsupported capability remains in the denominator.

## Body procedure and matrix

Current route: **Body → Scan your body** (or **New scan**) → **Open camera** → grant camera permission deliberately → **Find person** with the floor in view → fit head/feet/hands inside the selection → **Start scanning** → complete the native body ring → **Continue to details** → complete detail ring → **Capture more detail** if required → **Build my avatar** → review → **Use this avatar**. Keep the mannequin stationary; move only the phone. Build does not require manually entering height.

Admission is not an accuracy certificate: at least **60 distinct accepted aligned images**, **2 completed passes**, valid sample-ID/URL mappings excluding rejected samples, and retained positive finite depth on at least `max(20, ceil(acceptedImages/2))` images. DepthFloat32/DisparityFloat32 with one readable positive finite value establishes *presence*, not dense depth quality. UI shot count alone is insufficient. Sources: `AvatarScanInput`, `BodyCaptureModel`, `BodyScanCameraStatus`, `AvatarScanInputTests`, `AvatarScanTests`, `BodyScanUXTests`.

Every physical row below is **NOT RUN**. “Pass/fail” defines future observations, not measured results.

| Case | Controlled procedure / observation | Existing software evidence and future pass/fail criterion |
|---|---|---|
| Subject framing | Select a full-height nonpersonal target; deliberately crop head, feet or hands, then restore complete framing/floor. | SDK feedback and selection guidance must match; framing/selection must not start while tracking/issue guards block. A completed ring does not certify anatomical coverage. |
| Camera distance | Vary only distance from deliberately too close/far to a usable framing position; record actual reference distance if measured. | `objectTooClose`/`objectTooFar` guidance must appear/recover when SDK reports it. No validated metric operating-distance band exists. |
| Lighting | Repeat in diffuse even light, low light and backlighting; record measured illumination only with a suitable meter, otherwise qualitative labels. | SDK-reported low/dark feedback must map to visible guidance and initial-action gating. Usable lighting envelope remains unestablished. |
| Tracking quality | Acquire floor tracking, introduce brief camera motion/loss, then stabilize. | Non-normal tracking blocks initial selection/capture; guidance recovers. Completed-pass transitions intentionally do not depend on live framing warnings. |
| First capture pass | Follow body ring around the stationary target; observe explicit pause/checkpoint. | Native completion increments a pass once, pauses and offers Continue to details. One pass cannot admit reconstruction. |
| Second/detail pass | Continue explicitly, complete another ring; observe labels and optional extra detail. | At least two confirmed passes required; stale completion must not count twice. Different pass heights and regional coverage are not automatically verified. |
| Minimum photo coverage | Record live shot count, then final accepted aligned count/outcome, including rejected inputs. | Fewer than 60 accepted unique aligned files or fewer than two passes must reject. Duplicate aliases/missing mappings cannot inflate coverage. |
| Depth availability | Exercise supported LiDAR capture, then conditions degrading depth; retain abstract rejection/outcome. | Invalid formats/nonpositive/nonfinite depth or insufficient retained depth-bearing aligned inputs must reject. Presence is not registration/density/accuracy validation. |
| Reconstruction completion | Build only after capture admission; observe model-request progress, final result and failure recovery. | Native model and poses must complete, final input must revalidate and textured geometry must admit. Auxiliary progress cannot prematurely finish the model. Simulator cannot exercise this native success path. |
| Model scale | Compare rigid target bounds against independently measured references using the fit-roadmap protocol. | Existing finite/plausible bounds/scale guards must hold. Depth-mode scale near one is true by construction, **not** measured dimensional accuracy; physical error budget remains a release gate. |
| Texture quality | Use nonpersonal matte/color targets; inspect front/side/back review for texture coverage, seams and registration. | Existing texture/nonempty geometry checks must admit only usable structural input; mere presence cannot pass texture-fidelity validation. Record missing/smeared/misaligned regions. |
| Missing geometric regions | Inspect all sides and difficult regions on the nonpersonal target; log a region-by-region completeness map. | The app has no anatomical/region-completeness certificate. A ring/count/bounds pass does not satisfy this gate; missing regions remain failures for later accuracy approval. |
| Storage and reopening | Save the admitted nonpersonal model, leave/relaunch validation app, reopen and rotate. | Exact committed model/hash/calibration reloads; texture and scale survive. Failed replacement must preserve the previous saved avatar. Raw capture inputs follow existing cleanup. |
| Scan deletion | Explicitly delete only the validation model; relaunch and inspect independent manual/Closet data. | Active manifest/model clears and unrelated records remain. Corrupt data is retained until explicit recovery/deletion, never silently discarded. |
| Capture interruption | Background/lock at framing, each pass and reconstruction; foreground again. | Attempt is intentionally abandoned with recovery, not falsely completed; saved avatar survives. Idle-timer state must restore. This is not seamless capture resume. |
| Retry behavior | Cancel/retake at each stage, then start a new attempt; probe photo-limit and pending-action recovery. | Stale async callbacks cannot affect the new attempt. Camera-action timeout is eight seconds; capacity/failed selection must offer honest recovery. No partial failed attempt becomes an avatar. |

## Shirt procedure and matrix

Current route: **Closet → Add clothes → Scan a shirt → Continue to camera**. Use one ordinary short-sleeved shirt, flat on a horizontal contrasting surface, collar at the top of upright portrait view, sleeves spread and all edges visible. Hold directly overhead; follow live guidance until three distinct agreeing candidates produce review. Save only after inspecting the result. **Restart scan** resets the camera child; Cancel/reopen also starts a new scan. For an existing photo-only entry, use its scan/retake flow; failed replacement must preserve the prior image/record.

Every physical row below is **NOT RUN**. Sources: `AutomaticGarmentScanView`, `GarmentCaptureCamera`, `GarmentImageProcessor`, `GarmentDepthAnalyzer`, `GarmentPlaneProjection`, `GarmentLandmarkDetector`, `ClosetStore`, `ClosetTests`, `Vendor/GarmentIQ/NOTICE.md`.

| Case | Controlled procedure / observation | Existing software evidence and future pass/fail criterion |
|---|---|---|
| Shirt recognition | Repeat with ordinary nonpersonal shirts and negative/non-shirt scenes; retain every rejection/outcome. | Exactly one plausible foreground/outline and required model output must pass; ambiguous/clipped inputs reject. Licensed-photo inference is not camera recognition-rate evidence. |
| Collar orientation | Test instructed collar-up portrait arrangement, then deliberately rotate collar down and restore. | Orientation/neck-above-shoulder/hem-order guards and guidance must respond honestly; unsupported orientation must not be represented as validated. |
| Sleeve visibility | Spread both short sleeves, then crop/fold one and restore. | Outline/landmark association must reject invalid geometry rather than invent a span. Long-sleeved/sleeveless garments are unsupported research probes, not approved categories. |
| Foreground separation | Vary contrast and introduce a second/overlapping item, one condition at a time. | Exactly one foreground instance and conservative silhouette/edge checks required. Incomplete or ambiguous separation must not silently yield dimensions. |
| Depth consistency | Hold overhead above the flat shirt; vary tilt/depth conditions and restore. | Tracking/depth/confidence/format checks, camera overhead condition, high-confidence sampling and plane-spread guards must reject bad input. Existing 35-sample/coverage/25 mm spread guards are software sanity thresholds, not physical error guarantees. |
| Landmark detection | Observe points indirectly through stage/rejection/result; independently label defined endpoints for later comparison. | Required 25-point schema and geometric/edge guards must hold. Heatmap scores are not calibrated accuracy probabilities; no physical landmark overlay/accuracy dashboard is implemented. |
| Estimated dimensions | Independently measure defined width, length and sleeve endpoints; compare full scan outputs and units. | Valid projected metric spans and image/measurement association must persist. A mathematical plane fixture or model-conversion image cannot serve as physical dimension truth. |
| Multiple-frame agreement | Hold the same setup still, introduce disagreement, then restart; repeat complete scans, not selected best frames. | Three distinct mutually agreeing frames and median result; disagreement, orientation, interruption/error reset consensus. Single-flight scheduling and >0.7 s interval are not end-to-end timing/accuracy guarantees. |
| Capture completion time | Record camera-entry → reviewable result and Save separately; repeat cold/warm sessions with retries and failures retained. | Stage diagnostics and wall time must be separated. No physical time-to-capture claim is approved; unsupported/failed runs cannot be omitted. |
| Retakes and recovery | Restart, deny/regrant camera permission via Settings, interrupt/background, and attempt replacement with a failing candidate. | Recovery instructions/unsupported-device fallback must be visible; stale frames cannot commit; failed or cancelled replacement must preserve original image, dimensions and reference selection. |

## Evidence record and release gates

For each run record: candidate commit, isolated validation bundle, device model/OS/SDK, anonymous fixture ID, independent reference method, actual conditions, case/stage, success/rejection/unsupported status, timing, operator observation and protected artifact location. Nonpersonal measured reference values may be retained locally; never invent values or publish personal captures. Repetition count and prospective accuracy/error budgets must be approved **before** a physical study, not fitted after seeing results; see [fit validation roadmap](ONYOU_FIT_VALIDATION_ROADMAP.md).

A future physical PASS requires reproducible observed outcomes, reference definitions and retained failures—not an attractive renderer, plausible bounds, internally agreeing frames or a simulator screenshot. Current blockers: unavailable authorized physical target/assets, no independent physical dataset, no measured repeatability/accuracy, and no approved physical error budgets. Native device signing/install/capture is NOT RUN. Camera-derived body likeness, motion tolerance and physically accurate garment fit remain unestablished.

The older `SCANNER_S1B_DEVICE_CHECKLIST.md` describes a different Debug front/side candidate scanner. Its privacy principles remain useful, but its internal launch flag, navigation and pre-avatar scope must not be substituted for this native Object Capture/Photogrammetry workflow.
