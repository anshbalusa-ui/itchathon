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

Body capture uses a single default phone placement: keep the phone stationary while the person turns as guided. Follow the current in-app framing and capture instructions. Do not require entering body measurements, two full turns or repositioning the phone to another placement. Capture admission and reconstruction decisions remain governed by the shipping source; do not infer a successful reconstruction, complete anatomy or dimensional accuracy from the guidance UI.

Scans describe captured visible surfaces, not hidden anatomy. Physical capture, repeatability and measurement accuracy require independent device validation; software fixtures and rendered UI do not establish them. Solo-capture usability remains physically unverified.

## Verification and limits

The PR #28 report describes successful quantized-model checks and native CPU inference against its upstream example for source fingerprint `5d3963a6f10f9992caf70b3fa27e35c712e7883eb79f6c20d2d7b63834172770`; this is historical software evidence, not a current-branch test receipt or physical accuracy result. The upstream example is a model-conversion fixture, not dimensional ground truth.

Current integration source and release evidence must be verified against its exact candidate; older PR #28 receipts are historical and do not validate the current scanner or branch. No physical LiDAR capture or measurement-accuracy study is established by the software evidence. The upstream example is a model conversion fixture, not dimensional ground truth. Device calibration, background, pose, folds, silhouette quality and landmark error can affect estimates. Compatible dimensioned shirt scans may be used by the existing illustrative try-on workflow; photo-only imports do not gain metric scale or verified fit. Physical fabric stretch, drape, pressure or body-size recommendations are not validated. See [device validation](ONYOU_DEVICE_VALIDATION.md) and the [fit validation roadmap](ONYOU_FIT_VALIDATION_ROADMAP.md).
