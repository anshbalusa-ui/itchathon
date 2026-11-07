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

Body reconstruction still uses Object Capture with a helper walking around a stationary person. Required height entry has been removed. Reconstruction checks that sufficient captured HEIC samples contain depth before accepting automatic scale. New records preserve native reconstructed scale; legacy height-calibrated records remain readable. Scans capture visible clothing and skin, not hidden anatomy. This is not yet a solo-scan workflow.

## Verification and limits

The quantized model preserved the required heatmap peaks on the upstream example. Native CPU inference in the simulator matched the converted model's landmark coordinates. CPU is explicitly selected in the simulator because its accelerated backend returned invalid heatmaps; physical iPhones use available Core ML accelerators. A confidence failure rejects a capture rather than saving dimensions.

Unit tests cover native inference, silhouette rejection, metric ray projection, capture consensus, qualitative comparisons, local persistence, scan replacement, reference selection, corrupted storage, and automatic body scale. UI tests cover the clean avatar viewer and capture/navigation flows without measurement fields. Bitrig's Project.json test runner does not support this configuration; tests were run from a temporary XcodeGen project with the same source and target specification. The app itself is built and previewed through Bitrig.

No physical LiDAR capture or measurement-accuracy study was performed. The upstream example is a model conversion fixture, not a dimension ground truth. Device calibration, background, pose, folds, silhouette quality, and landmark error can affect estimates. The app does not currently simulate fabric stretch/drape or render uploaded clothing on an avatar. Comparisons are flat garment comparisons against a known favorite, not validated body-fit predictions.
