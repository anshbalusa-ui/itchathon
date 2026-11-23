# On You — release acceptance checklist

This checklist separates current-branch verification from historical receipts and physical/distribution gates. Passing a PR #28 check is not a pass for the integration candidate. The PR #28 source fingerprint and its 439 Debug / 21 Release counts are historical evidence only; see [release readiness](ONYOU_FINAL_RELEASE_READINESS.md). The [consolidation report](ONYOU_FOUNDATION_CONSOLIDATION.md) records bounded integration checks and exact source identity. Full regression/Release/distribution verification remains pending.

## Integration/software gates

| Gate | Required evidence |
|---|---|
| Candidate identity | Record delivered branch/commit, source fingerprint and integration scope; inspect all changes against latest main and merged PRs. Do not treat an old PR base or receipt as current. |
| Fresh test/build matrix | Record exact candidate identity, command, environment, case identities/results and artifacts for each authorized check; report failures/skips honestly. The bounded integration smoke does not satisfy a full release matrix. Do not transfer older receipts or require physical testing to complete source consolidation. |
| UI regression coverage | Preserve existing test names and meaningful assertions for dimensions, Save/Cancel/History, actual rendered pixels, rotation/visibility/reset/reopen, recovery and Release exclusion. Driver synchronization must not suppress failures or weaken acceptance thresholds. |
| Privacy manifest | Preserve the single existing DiskSpace reason/verifier/assertion contract supplied by PR #29; do not duplicate PR #28's already-integrated fix. Verify actual candidate bundles as part of owner-run checks. |
| Release isolation and provenance | Check production/debug fixture boundaries, bundle resources, licenses and notices from the delivered candidate; do not infer current results from the PR #28 report. |

## Physical/device gates — NOT RUN

| Gate | Required future evidence |
|---|---|
| Compatible hardware and permission | On authorized supported devices, observe actual capability, deliberate camera permission, denial/recovery and interruption. A build or simulator path is not a physical result. |
| Body capture | Use one default phone placement with the phone stationary and the person turning as guided. Follow current UI guidance; do not impose measurements, two full turns or another placement. Record actual outcomes, retries and failures; do not substitute old scanner steps or counts. |
| Garment capture and dimensions | Use approved nonpersonal garments, current setup guidance and independently measured, like-defined output endpoints. Retain failed/unsupported cases. |
| Storage, lock, backup, deletion | Test on an authorized physical device, including locked-state, backup/restore and fault outcomes where approved. Source declarations and simulator checks are not hardware evidence. |
| Accessibility and stability | Exercise supported text sizes, VoiceOver, touch targets, orientations, motion preferences, interruptions, memory and thermal behavior on representative devices. Record observations rather than infer from screenshots. |
| Physical accuracy and fit | Preapprove independent references, study design, error/uncertainty budgets and review. Until passed, make no accuracy, fit, pressure, drape or sizing claim. See [fit validation roadmap](ONYOU_FIT_VALIDATION_ROADMAP.md). |

## Distribution — NOT RUN / NOT APPROVED

- Obtain owner approval before main merge, changing credentials, signing or distribution.
- Review authorized signing/profile, bundle identity, archive and distribution configuration on the final candidate.
- Review privacy disclosures, permissions, third-party SDK/assets, legal/support information, retention/deletion, backup behavior and store metadata against actual product behavior.
- Keep release claims aligned with executed evidence. Do not describe authored fixtures or historical PR #28 receipts as real-person scans or current integration results.
