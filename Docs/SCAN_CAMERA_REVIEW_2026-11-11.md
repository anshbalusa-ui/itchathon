# Scan camera video follow-up — 11 November 2026

The supplied recording showed a short-sleeved collared shirt repeatedly rejected before metric measurement, and body controls consuming much of the camera viewport.

## Implemented

- Admit closed collars without requiring an open neckline silhouette. Allow minor torso-edge variation; retain single-garment, sleeve proportions, learned landmark, calibrated depth, plane and dimension validation.
- Keep up to five recent valid shirt candidates for 12 seconds. Require three mutually agreeing dimensions including the newest candidate. Brief recognition or tracking misses retain good evidence; restart, rotation and interruption invalidate the capture appropriately.
- Full-screen cameras with glass header controls and rounded, frosted instruction panels. Supporting information scrolls at large text sizes. Replace the live body phase strip with the current circle, actual photo counts and completion actions.
- Live shirt surface distance, continuous red/amber/green position quality, directional instructions, and proportional haptics with a persistent mute control. No depth means an unknown reading. Position updates at most five times per second; heavy recognition remains bounded to one in-flight frame.
- Guidance accounts for the actual ARKit image-to-viewport transform, including aspect-fill cropping on the phone's screen. Metric dimensions continue to use each frame's camera intrinsics, resolution, transform and high-confidence depth. No universal LiDAR field-of-view angle or model-name whitelist is assumed. Overhead tilt tolerance is about 26 degrees; metric projection and plane checks still apply.
- Body capture exposes native live near/far feedback plus explicitly labeled depth from the last captured, masked photo, expiring after five seconds. Sampled-photo torso/leg visibility counts come from actual recognized joints. These counts do not assert complete surface coverage or change capture acceptance.
- Enlarge the avatar review viewport without changing metric model scale. Display depth-derived height.
- Photo-only saves preserve the normalized original image without recognition or cutout. They supply no measurements or try-on. A depth capture retains its own image and does not offer an additional photo replacement that would erase its dimensions.

## Evidence

Temporary test projects and results live at `/tmp/onyou-video-review`; personal recording frames are not committed or published.

- `Recorded.xcresult`: the actual shirt frame from the video passed native Vision foreground extraction, outline admission, Core ML landmarks, exact-image pattern evidence and try-on pattern parsing on the iPhone 17 Pro Max, iOS 27.0.1.
- `Guidance.xcresult`: 25 focused simulator checks passed; camera-chrome renders use a visibly synthetic backdrop.
- `DeliveryPhone.xcresult`: 33 phone tests passed, including the recorded shirt, licensed-photo pipeline, consensus tolerance/expiry, projection, missing/stale depth, mask/confidence filtering, photo preservation, body UI and rendered try-on.
- `LiveCamera.xcresult`: physical camera UI, numeric depth/guidance, restart and closing without saving passed on the phone. Inspected its actual camera screenshot. The camera faced the desk, not a shirt; this is not a live garment-dimensions accuracy result. Xcode reported an internal QoS warning and failed optional diagnostic collection; the test itself passed.
- `Ready.xcresult`: 31 final focused checks passed on the physical phone, with zero failures or skips. This includes actual-preview crop handling, final wrapping/scrolling layouts and the live camera restart flow.
- Bitrig's `test` command exits 78 for this Project.json project. Tests therefore use an external temporary XcodeGen project with Xcode's runner. App builds and delivery use Bitrig with the iOS 27.0 SDK and the existing bundle identifier.

Final delivery: signed Bitrig device build succeeded with the iOS 27.0 SDK (`2026-11-11T13-51-11-ba01818e.log`). `bitrig run` launched that normal Debug artifact on the connected iPhone using the existing identity, without fixture/test launch arguments. `bitrig preview -platform iOS -scheme FitCheck` also passed compilation; the built-in preview remained paused, so phone delivery used the explicit build/run commands.

## Public API limits and remaining physical checks

Apple's Object Capture view owns its point-cloud rendering and coverage ring. The iOS 27.0 public API provides no point-cloud replacement switch, live metric camera-distance stream, or body-region surface-completion map. The app does not invent any of these. Body numerical distance requires a saved sample with supported depth and a foreground mask; otherwise it stays unavailable. Its live near/far haptics are qualitative, while shirt guidance has continuously scaled distance quality and haptic intensity.

A custom body capture engine would be required to replace those native visuals and supply continuous body distance/region coverage. This change preserves Apple's capture and reconstruction pipeline. Complete real-person capture, reconstruction accuracy, garment dimensions against a ruler, and the feel of haptics through actual near/far movements still need a fresh physical session. No pressure, stretch or calibrated clothing-fit claim is made.
