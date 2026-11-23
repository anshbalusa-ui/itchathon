# On You — physical fit validation roadmap

## Status and evidence boundary

Physical body-measurement accuracy, garment-dimension accuracy and physical fit are **NOT ESTABLISHED** for the integration candidate. The historical PR #28 report's simulator render matrices and authored fixtures demonstrate software rendering for its exact source snapshot, not independent metrology or fit. No garment size, hidden anatomy, fabric stretch, pressure, drape or movement claim follows from visually plausible rendering.

Current physical procedure begins with a single default phone placement and a stationary phone while the person turns as guided. No required measurements, two full turns or additional placements are presumed. Any later protocol must use the actual current app instructions and must not weaken admission thresholds to manufacture a successful sample.

## Questions that require independent evidence

| Topic | Prospective reference method | Claim not established by software alone |
|---|---|---|
| Body capture repeatability | Repeat complete nonpersonal-target captures under predeclared positions/lighting/device conditions; retain retries and failures. | A successful capture or smooth model does not show repeatability, completeness or body likeness. |
| Body dimensions | Independently measure named rigid/mannequin references using a calibrated, documented method; compare only like-defined dimensions/surfaces. | A scale inferred from the same reconstruction is not an independent reference. |
| Shirt dimensions | Define the exact output endpoints before collecting data; independently measure the same spans on conditioned, flat garments and repeat full scans. | A retailer size label, generated fixture or conversion image is not dimensional truth. |
| Projection and landmarks | Independently annotate endpoint locations and reference camera/depth calibration; retain rejected/ambiguous cases. | Confidence scores and internally agreeing frames are not calibrated physical error estimates. |
| Fabric thickness and stretch | Measure nonpersonal material samples under a defined conditioning/contact/load protocol, including direction and recovery. | Render spacing or geometric offsets are not textile thickness, strain or pressure. |
| Drape and movement | Compare with independent garment-surface observations on a measured form and repeatable pose/motion protocol. | A static render, orbiting camera or shirt-shell mesh does not validate drape or dynamic fit. |
| Fit/sizing recommendation | Define intended use and independent cohort/reference, preapprove uncertainty and error budgets, and review all outcomes. | No size recommendation is justified by illustrative fit, hull clearance or plausible body bounds. |

## Study controls and reporting

Before collecting data, approve the use case, nonpersonal target/garment provenance, endpoint definitions, instrument calibration, repeat count, uncertainty method and acceptance limits. Limits must be prospective, not selected after seeing results. Keep anonymized fixture codes, failed/unsupported attempts, environmental conditions, software commit and references together in controlled local evidence. Do not commit personal scans or publish identifying device data.

For scalar outputs, report signed and absolute error, bias, variability across complete sessions, reference uncertainty, rejection/retry rates and all excluded cases with reasons. For surfaces, disclose registration, correspondence, incomplete regions and distance distributions. For clothing contact, disclose reference thickness and registration uncertainty before interpreting clearance. A mannequin result cannot establish human likeness or performance.

## Sequence

1. Establish nonpersonal independently measured references and approve prospective protocol/budgets.
2. Validate the current default-placement body workflow on authorized compatible hardware; retain all outcomes and characterize completeness/repeatability.
3. Validate garment endpoints, projection and landmarks against independent garment references.
4. Only with measured material/construction evidence, evaluate separate drape or motion research requirements.
5. Obtain independent review before any physical accuracy, fit, pressure or sizing claim.

Until those gates pass, describe only implemented software and illustrative rendering. The offline product scope and separate future integrations are covered by the integration's Execution Roadmap, not a second post-MVP roadmap.
