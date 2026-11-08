# On You scan algorithm audit

Reviewed the shipping `OnYouRootView` flow, body capture, reconstruction acceptance, saved mesh calibration, and closet measurement/comparison code. The older scanners and fit engine are not wired into this flow.

## Remaining product and accuracy gaps

| Priority | Finding | Evidence and consequence |
| --- | --- | --- |
| High | The scanned avatar does not drive garment fit. | `OnYouRootView` passes only `ClosetStore` to the closet. `BodyCaptureModel` saves a textured mesh; it does not extract chest, waist, hips, or anatomical landmarks. Closet comparisons use a reference shirt. Garment draping onto the scanned person is unimplemented. |
| High | Scale sanity is not accuracy validation. | `ScannedAvatarGeometry` derives reference height from the reconstructed bounds. For depth-scaled scans, the resulting scale factor is one by construction. Bounds checks reject implausible outputs but cannot establish dimensional error. Depth presence, image counts, and aligned camera poses are acceptance guards, not precision measurements. |
| High | This remains photogrammetry of a clothed, stationary surface. | Body motion can spoil correspondence between photographs. Clothing hides the underlying body. There is no motion compensation, independent body-shape estimation, or face-specific likeness validation. A plausible textured object can pass the current mesh checks. |
| Medium | Coverage is not anatomically validated. | Native ring completion records camera coverage. The app does not verify that the detail pass was actually at a different height, that every anatomical region reconstructed, or that aligned images still cover all sides after rejection. |
| Medium | Garment consistency does not establish garment accuracy. | The LiDAR plane projection has a metric fixture test, and GarmentIQ inference has a conversion fixture test. Repeated frames reject inconsistent dimensions but cannot detect a shared segmentation, landmark, or depth bias. Only flat short-sleeved shirts are supported. There is no fabric stretch or drape model. |

The height bounds still use the existing measurement range, so very short or very tall people can be rejected. No accuracy or likeness claim should be based on the synthetic box, shirt silhouette, or rendering fixtures.

## Corrections made in this review

- Capture capacity now has a visible retake action. A late native pass-completion update can still make the capture ready; capacity does not immediately destroy the attempt.
- Pass and shot observers reconcile current SDK values through one method. Starting another pass does not count a stale completed ring again or immediately pause before its reset arrives.
- Reconstruction preflight counts saved image files rather than trusting the camera's shot counter. Depth buffers with no positive finite samples, or an unsupported pixel format, no longer qualify as depth evidence.
- Reconstruction requests Apple's camera poses. Final acceptance uses distinct input URLs corresponding to poses actually used by reconstruction, excludes rejected sample IDs, and checks retained depth evidence. Missing mappings, repeated URLs, insufficient aligned input, and loss of depth evidence fail closed. Saved image counts reflect accepted input.
- Input and pose file URLs resolve filesystem aliases before comparison, avoiding false rejections from equivalent `/var` and `/private/var` paths. Aliases to the same photo cannot inflate coverage.
- Build progress and time estimates track the model request, so the auxiliary pose request cannot make the model appear finished early. Existing reconstruction ordering is preserved; reversing direction alone has not been shown to explain the recorded failure.
- Cancellation is rechecked after every asynchronous sample load, including the final image, before it can start reconstruction or modify a newer attempt.
- The discard prompt pauses capture. Dismissing it resumes only an unfinished circle. Auto-lock is disabled during preparation, capture, and reconstruction, then the prior setting is restored.
- The closet photo comparison no longer claims exact shared scale; cropping and camera angle affect its visual alignment.

## Verification and limits

Regression coverage includes photo-limit recovery, late pass completion, saved-versus-aligned image counts, rejection of depth-bearing input, missing or duplicate pose mappings, odd image counts, padded depth rows, invalid depth values, and unsupported pixel formats. Existing storage, projection, inference, and scan-navigation checks remain applicable. Camera layouts use explicitly synthetic rendering fixtures.

Passing suites: `AvatarScanInputTests`, `AvatarScanTests`, `BodyScanUXTests`, `ClosetTests`, and `OnYouUITests`, with a further input-suite rerun for filesystem aliases. Tests used the generated XcodeGen test project because `bitrig test` does not support this checkout's `Project.json` configuration. App previews use `bitrig preview -platform iOS`.

Still required: paired-device capture through reconstruction, repeated scans of people who can hold the requested pose, independent dimensional references, regional mesh-completeness checks, and visual comparisons of face and skin texture. App code cannot establish these from a screen recording. Locking the phone or backgrounding the app still intentionally abandons an in-progress attempt; the previously saved avatar is preserved.

## Apple references checked

- [Object Capture image limits](https://developer.apple.com/documentation/realitykit/objectcapturesession/maximumnumberofinputimages)
- [Photogrammetry camera poses](https://developer.apple.com/documentation/realitykit/photogrammetrysession/request/poses)
- [Sample-to-file mapping](https://developer.apple.com/documentation/realitykit/photogrammetrysession/poses/urlsbysample)
- [Depth data and scale](https://developer.apple.com/documentation/realitykit/photogrammetrysample/depthdatamap)
- [Photographing static objects and avoiding deformation](https://developer.apple.com/documentation/realitykit/capturing-photographs-for-realitykit-object-capture)
