# On You — release readiness

## Current integration status

This document records evidence boundaries for the foundation integration candidate, not a release, physical-accuracy or distribution approval. [The consolidation report](ONYOU_FOUNDATION_CONSOLIDATION.md) owns any newly executed bounded integration checks and their exact source identity. Full regression/Release/distribution and performance evidence is not established by this source review or older candidate receipts.

PR #28 (`16dccd39162dfcb3519d3cfc8f7211446b6d5b24`) is a historical review candidate, not an integration baseline. Its own release-readiness report identifies source fingerprint `5d3963a6f10f9992caf70b3fa27e35c712e7883eb79f6c20d2d7b63834172770` and reports 439 Debug and 21 Release cases, prior simulator/build/manifest checks and a performance study for that source snapshot. Those numbers and artifacts remain historical receipts for that exact candidate only. They do not establish test identities/results, build status, scanner behavior, privacy state or performance for the current branch, PR #29, or later source. Physical capture and distribution were explicitly NOT RUN in that report as well.

The PR #28 receipt includes a DiskSpace required-reason privacy change. It is not re-applied while adapting #28: consolidation imports PR #29's identical reason, verifier expectation and assertion exactly once.

## Preserved UI coverage and test-driver adaptations

The integration `UITests/TryOnUITests.swift` retains existing test identities and behavior assertions, including shirt dimension values, measurement Save/Cancel and History, actual rendered-pixel changes, garment rotation/visibility/reset/reopening, scan-required recovery, supported capture-entry UI and Release fixture exclusion. The older branch snapshot lacks some later main coverage and uses older scan identifiers; those inherited differences are not PR #28's unique delta and are not copied over current `scan.unsupported` / `scan.camera.action` assertions.

Adopted test-driver-only changes are limited to source-grounded synchronization and gestures: wait for the reopened measurement editor's cancel control before addressing its lazy row; avoid querying native Form row hit-testing until its frame is nonempty and on-screen; use a short, slow interior Body-controls swipe; and, when a collection list is present, scroll its gutter rather than dragging its interactive 3D content. These changes alter test interaction, not application behavior or acceptance thresholds. Any scoped execution is recorded in the consolidation report; this is not a new full-UI-suite receipt.

Smooth commit `3d96b671bbef02bc4156d3fb9a031173d4ad0658` independently adds a longer manual-measurement/rendering journey. That extra case and its exact updating-status wording predicate were not copied: current tests already wait for visible body pixels and an actual rendered change. Its compatible async lifecycle source is adapted separately, with saved-scan precedence and generation fencing; broader remeshing/section changes remain explicitly deferred.

## Physical and distribution status

The current physical body capture and garment dimension workflows are **NOT RUN**. Use [device validation](ONYOU_DEVICE_VALIDATION.md) for the single-default-placement, stationary-phone/person-turn procedure and evidence limits. No synthetic fixture, historical phone result, SDK support declaration or successful simulator scene establishes physical capture, anatomical completeness, dimensional accuracy, fit, fabric response or sizing. Do not require user-entered measurements, two full turns or extra phone placements unless the current approved product workflow explicitly changes.

Signing for distribution, archive, legal/privacy-label review, TestFlight/App Store submission and publication are **NOT RUN / NOT APPROVED**. Owner approval and fresh verification of the delivered candidate are required before any release assertion. Use the [release checklist](ONYOU_RELEASE_CHECKLIST.md) for gates and [fit validation roadmap](ONYOU_FIT_VALIDATION_ROADMAP.md) for prospective independent measurement work.

## Deferred / not imported

- Superseded inherited body-scanner procedures, thresholds, navigation identifiers and route assertions from the older branch snapshot: preserve the current scanner and instructions instead. These are not attributed to PR #28's unique commit.
- PR #28's DiskSpace privacy fix: already provided by PR #29; no duplicate edit.
- PR #28's post-MVP roadmap: omitted because the integration's new Execution Roadmap supersedes it; do not create a second roadmap.
- Broad release/distribution, physical accuracy and performance claims: no current approval. The consolidation report distinguishes any actual bounded checks from historical evidence; no old receipt supplies a current pass.
