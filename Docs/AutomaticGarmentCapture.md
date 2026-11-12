# Automatic garment capture

On You uses GarmentIQ's pretrained HRNet garment landmarks, converted to Core ML and bundled in the app. It does not call Size AI or any other measurement service. The model architecture, license, schema, pinned upstream revision, and weight checksum are recorded in `Vendor/GarmentIQ`. `Scripts/convert_garmentiq.py` reproduces conversion and checks required landmark positions against the original network on an upstream sample.

## Capture flow

- Closet → Add clothes → Scan a shirt.
- Lay a short-sleeved shirt flat on a horizontal, contrasting surface, collar toward the top of the portrait camera view.
- Vision finds a single foreground instance. Conservative silhouette checks reject incomplete or ambiguous shapes.
- GarmentIQ locates armpits, neckline, shoulder, and hem landmarks. Required heatmaps must have sufficient scores; keypoints are checked against the foreground outline. Scores are not calibrated accuracy probabilities.
- ARKit's intrinsics, camera transform, and high-confidence scene depth establish metric scale. A median horizontal plane is fitted to foreground depth; excessive depth spread or camera tilt rejects the frame.
- Automatic capture requires mutually consistent estimates across separate frames. The saved estimate uses their median. Camera interruption, orientation change, or low-quality results clear the pending consensus.
- Save the cutout locally. Mark a scanned shirt whose fit you like as your reference; compare other scans using qualitative width, length, and sleeve-reach differences.

Imported product photos and screenshots are saved without dimensions. A product link can be attached, but On You does not scrape retailer measurements or infer scale from arbitrary photos. A saved photo can later be upgraded through a live depth scan; image replacement and metadata persistence preserve the original until the replacement is committed.

## Body capture

Body → Scan your body is the sole body-capture entry point. Closet uses a single toolbar Add action. The body flow now opens full screen. Camera controls sit outside the live preview so they do not cover the person or Apple's capture animation. A persistent stage path distinguishes framing, the body circle, detail capture, and building. Photo-detail progress reflects the actual captured-image threshold; circle completion still comes from Object Capture's coverage signal, not a timer. Actions show pending states, failed selection explains how to include the floor, and leaving an active capture requires discard confirmation.

During reconstruction, progress and estimated time come from Apple's reconstruction outputs. The app shows an indeterminate state until progress is available and never fabricates a capture countdown. Elapsed capture time follows the actual capture start. The interface has rendered checks at standard and accessibility text sizes; those render fixtures do not exercise real camera capture.

Body reconstruction still uses Object Capture with a helper walking around a stationary person. Required height entry has been removed. Reconstruction checks that sufficient captured HEIC samples contain depth before accepting automatic scale. New records preserve native reconstructed scale; legacy height-calibrated records remain readable. Scans capture visible clothing and skin, not hidden anatomy. This is not yet a solo-scan workflow.

## Verification and limits

The quantized model preserved the required heatmap peaks on the upstream example. Native CPU inference in the simulator matched the converted model's landmark coordinates. CPU is explicitly selected in the simulator because its accelerated backend returned invalid heatmaps; physical iPhones use available Core ML accelerators. A confidence failure rejects a capture rather than saving dimensions.

Automated coverage includes native inference, silhouette rejection, metric ray projection, capture consensus, qualitative comparisons, local persistence, scan replacement, reference selection, corrupt storage, automatic body scale and actual native try-on rendering/navigation. The separate manual measurement editor is not part of the camera scanner and does not create an authorized captured avatar. Use `Scripts/verify_development.py` with the actual `Project.json`/On You project for the current complete matrix; exact fresh results are recorded in [release readiness](ONYOU_FINAL_RELEASE_READINESS.md).

No physical LiDAR capture or measurement-accuracy study is established by the existing software evidence. The upstream example is a model conversion fixture, not dimensional ground truth. Device calibration, background, pose, folds, silhouette quality and landmark error can affect estimates. Compatible dimensioned shirt scans can be rendered on an admitted saved avatar through the existing illustrative try-on; photo-only imports do not gain metric scale or verified fit. There is no physically validated fabric stretch, drape, pressure or body-size recommendation model. See [device validation](ONYOU_DEVICE_VALIDATION.md) and the [fit validation roadmap](ONYOU_FIT_VALIDATION_ROADMAP.md).
