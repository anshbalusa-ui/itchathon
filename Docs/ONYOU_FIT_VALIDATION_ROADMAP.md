# On You — physical fit validation roadmap

## Status and boundary

**Working:** interactive illustrative shirt-on-saved-avatar rendering, actual connected garment geometry, orientation/rotation, visibility, switching, saved inputs, cancellation and recovery. These are implemented in PR #26 and retained by PR #27. Current synthetic native render matrices exercise body A/B × Tide/Coral × five viewing angles; they do not establish physical fit.

**NOT ESTABLISHED:** body/garment measurement accuracy, fabric stretch, pressure, material drape, dynamic behavior, anatomical likeness or a sizing recommendation. No physical validation data was available for this readiness pass. A visually plausible shirt is not evidence that a real garment will fit. No new cloth engine or synthetic research prototype is added: without independent scale/material/contact evidence another simulation would multiply assumptions rather than validate the MVP.

Real-device capture procedures and current NOT RUN matrix are in [device validation](ONYOU_DEVICE_VALIDATION.md). Final software/performance evidence is in [release readiness](ONYOU_FINAL_RELEASE_READINESS.md).

## What the existing components actually provide

| Existing component | Supported calculation / evidence | What it cannot establish |
|---|---|---|
| `AvatarScanInput`, `BodyCaptureModel` | Native accepted photo/pose/depth mappings, coverage, reconstruction lifecycle and finite positive depth presence. | Dense coverage, independent scale accuracy, anatomical completeness or hidden body shape. |
| `AvatarScanRecord`, `AvatarScanCalibration`, `AvatarScanStore` | Positive finite plausible bounds, recorded calibration, protected local artifacts, integrity hash and compatible reopening. In depth mode reference height derives from the reconstruction and scale is effectively one. | A near-one scale or valid SHA is not an independent dimensional/likeness measurement. |
| `BodyShapeKernel`, Debug `MeasurementAvatarGeometry` | Generic authored human meshes change actual vertices for supplied height/chest/waist/hip/shoulder inputs; section targets and normal/topology behavior have software tests. | Entered numbers do not measure a user; matching template sections does not reconstruct a person's anatomy, face or posture. Manual illustration remains separate from authorized captured-avatar try-on. |
| `GarmentDepthAnalyzer`, `GarmentPlaneProjection` | Calibrated camera rays intersect a locally estimated horizontal plane; admitted points yield metric projected spans. Portrait/native UV conversion, confidence/tracking/plane guards and finite ranges are tested. | A plane fixture, point score or internally agreeing frames is not physical calibration, textile thickness or absolute accuracy. |
| GarmentIQ landmark service, outline and pattern evidence | One model/prediction at a time, 25-point schema, required-point/outline/order checks, original-image association and retained observed points. | Heatmap scores are not calibrated likelihoods of physical correctness; a conversion photo is not dimension ground truth. |
| `TryOnSceneGeometry`, `TryOnSurface`, pose estimator | Full scene transforms, unit-aware observed triangle sections, standing orientation, finite indexed geometry and sampled front/back depth. | Body landmarks are geometric references, not clinically validated anthropometry or inferred skin beneath clothes. |
| `TryOnClothingEnvelope` | A consistent convex clothing envelope around admitted observed sections, including the region below the hip reference. | The hull intentionally spans concavities; it is neither hidden skin nor a fitted anatomical body. |
| `TryOnGarmentShell`, `TryOnGeometry` | Connected illustrative torso/sleeves, bounded sampling, explicit openings, texture mapping and sampled separation from the observed surface. | It has no material law, real textile thickness, sewing-pattern validation, gravity/contact dynamics, stretch, pressure or movement simulation. The rear material is inferred, not captured detail. |
| `TryOnModel` / owned scene caches | Safe asynchronous preparation, staged loading, cancellation, no stale selection and bounded presentation ownership. | Caching/visual responsiveness does not improve physical accuracy. |

### Lock the estimands before collecting reference data

The current shirt **body width** is the projected distance between validated landmarks 11 and 19. **Length** is neck landmark 1 to the hem level from landmark 15 at the neck's horizontal coordinate. **Sleeve span** is the silhouette's left-to-right sleeve span: it is not a single shoulder-to-cuff sleeve length. `GarmentDepthAnalyzer` constructs `GarmentScanDimensions` from those spans. Reference measurement instructions must match these exact definitions or explicitly declare a different future estimand. Do not compare retailer size labels or a catalogue's differently defined “length” to this output.

A flat body-width span must not silently become body circumference or a ready-to-wear size. Likewise, template torso-section perimeter, observed outer-clothing perimeter, hull perimeter and anatomical girth are different quantities. The app's discrete section/depth/shell sampling distances and display offsets are numerical parameters, **not validated error bounds or fabric thickness**.

## Validation matrix: missing data and release gates

All physical study rows remain **NOT RUN**. Proposed protocols below are requirements for later evidence, not fabricated observations. Use nonpersonal rigid/mannequin/garment assets first; there is no request for private body scans.

| Required topic | Independent reference and prospective procedure | Missing evidence / acceptance gate |
|---|---|---|
| Body-scan dimensional accuracy | Independently measure a rigid calibration target and marked mannequin dimensions with calibrated instruments; capture from varied directions/distances and compare corresponding registered visible surfaces/sections. Record crop, clothing and pose explicitly. | Absolute/signed/relative error by region, registration method, missing areas and uncertainty. Native depth cannot validate itself; approve use-case error budgets before study. Mannequin accuracy is not proof of real-person likeness. |
| Shirt-scan dimensional accuracy | Lay a relaxed shirt flat under a defined conditioning/tension protocol. Independently measure the same body-width, neck-to-hem-level and total sleeve-span endpoints; independently label model points and compare camera estimates. | Endpoint definitions, repeated reference readings, camera/depth calibration, uncertainty and projection/landmark error decomposition. No inference from a retailer's size chart. |
| Repeated measurements | Repeat complete scans across independent sessions, positions, lighting and approved compatible devices; randomize order and retain failures/retries, not only favorable frames. | Prospective sample size from the chosen precision goal; within/between-session bias, standard deviation, limits/distribution and rejection rate. Three agreeing frames are not three independent accuracy studies. |
| Fabric thickness | Measure nonpersonal material coupons using a defined instrument/contact load and conditioning protocol; record compressibility and seam/layer regions separately. | Real thickness distributions, measurement uncertainty and how thickness maps to a geometric surface. Existing shell offsets are not thickness. |
| Fabric stretch | Measure warp/weft/bias load–extension curves, cycling, recovery/hysteresis and directionality under defined conditions. | Material constitutive evidence and validated solver requirements. Photographs/depth, clearance or small flat dimensions do not imply strain, stiffness or pressure. |
| Garment drape | Observe a known garment on an independently measured rigid/mannequin form in a defined static pose; acquire independent front/side/back garment-surface references under controlled gravity/conditioning. | Reference drape folds/hem/sleeve positions and surface error, not visual preference alone. Captured input and independent reference must not be the same unvalidated pipeline. |
| Movement behavior | Start with an approved articulated nonpersonal rig and repeatable motions; separate rigid motion from material deformation. A human study requires its own authorization/consent/privacy plan and is outside this pass. | Time-resolved references, pose/contact consistency, motion artifacts and material response. Camera orbiting a static mesh is not dynamic cloth validation. |
| Surface clearance | Register independently measured form and garment surfaces, account for garment thickness, and compare signed-distance/contact regions under a defined pose. Evaluate discretization/registration uncertainty. | Which surfaces/side of fabric are compared, sample density, true contact reference and uncertainty. Positive rendered spacing or “closer” labels must never be presented as verified pressure. |
| Different shirt constructions | Cover approved short-sleeved constructions/materials, seams, necklines, sleeve attachment, asymmetric patterns and layered/thick regions as separately recorded strata. Long sleeves, sleeveless garments and other categories require explicit later approval. | Model applicability and metrology evidence by construction; do not generalize one tee's agreement to all garments. New categories are not required to complete the current offline MVP. |
| Independently measured real garments | Assign anonymous fixture IDs to ordinary test garments, retain calibrated reference definitions/readings/photos locally, and compare repeated app outputs with blinded independent measurements. Track all failures and provenance. | Ground-truth dataset, calibration records, repeatability, uncertainty and reviewable error report. No invented garment measurements, inventory, availability, retailer identity, price or sizing guarantee. |

## Measurement analysis and approval

Before a physical study, approve intended use, supported device/OS/assets, endpoint/region definitions, repeat counts, uncertainty method and acceptance budgets. Budgets remain **unapproved**, not implicit promises. A technical reviewer must sign the prospective protocol before results are seen; do not choose tolerances after observing the errors.

For an independently referenced scalar, report signed error `estimate - reference`, absolute error, bias, median/mean absolute error, high-percentile absolute error and reference uncertainty. Relative error requires a positive meaningful reference and must not hide a large absolute error. Report within-session and between-session variability plus failure/unsupported/retry rates. For surfaces, disclose alignment, correspondence, incomplete regions and bidirectional distance distributions rather than only bounding-box height. For contact/clearance, disclose both reference thickness and registration error before interpreting millimetres.

Do not promote a software numerical tolerance, calibration sanity range, depth-plane spread, model confidence or consensus threshold into a physical accuracy result. No body measurement or clothing size is recommended from these unverified assumptions.

## Unverified assumptions to keep visible

- The reconstruction is a visible outer surface, often including clothing—not permission to infer the body underneath.
- Standing body orientation and geometric shoulder/hip references are sufficient for a static illustration, not every body pose or anatomy.
- Three flat shirt spans and one front cutout cannot fully specify a sewn 3D garment, fabric properties or rear design.
- The convex clothing envelope, numeric clearance, body-contour proximity and “needs room” heuristic are illustrative, not ease/strain/pressure measurements.
- Plausible bounds, a complete ring, a matching hash, a smooth mesh, a successful renderer and repeatably biased estimates can all coexist with incorrect physical dimensions.

## Ordered future work, without replacing the MVP

1. **Metrology and provenance first:** approve definitions/budgets and build independent nonpersonal calibration/reference data with controlled access and reproducible procedures.
2. **Validate current capture:** complete device matrix, document device/lighting/pose limits, repeatability and missing-region behavior. Keep failed evidence and existing admission thresholds.
3. **Validate current geometric calculations:** isolate projection, landmarks, scale, surface sampling and image/measurement association against the independent references.
4. **Characterize materials and garment patterns:** obtain measured material/construction data before choosing any physical model. A research model needs separate requirements, test data, ownership/privacy and validation gates.
5. **Only if justified, isolated research:** an internal development flag may host a future experiment after approved evidence and requirements exist. It must not replace the shipping illustrative path, relax authorization, claim verified fit or add a sizing recommender by default.
6. **Physical claim review:** a calibrated, repeated, independently reviewed study is required before any accuracy/fit/pressure/sizing claim or release promotion. Until then the status is illustrative software with physical validation pending.
