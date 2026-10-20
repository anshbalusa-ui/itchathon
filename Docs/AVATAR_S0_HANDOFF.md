# Segment 0: isolated avatar-first foundation

Scope: strengthen PR #7, not implement the scanner or a consumer-ready avatar experience. No camera capture, body geometry estimation, mesh, catalog, fit prediction, retailer connection, or external component was added.

## Repository assessment

- Inspected `main` at `562173f`, scanner PR [#5](https://github.com/anshbalusa-ui/itchathon/pull/5) at `771540b`, planning PR [#6](https://github.com/anshbalusa-ui/itchathon/pull/6) at `6936d92`, and foundation PR [#7](https://github.com/anshbalusa-ui/itchathon/pull/7) at `84312c5`. All three PRs were open drafts. This branch starts from #7; no PR was merged.
- `project.yml` remains canonical: native SwiftUI, Swift 5.10, iOS 17 minimum, app/unit/UI targets, no third-party runtime dependencies. Generated Xcode projects are ignored.
- `FitCheckApp` owns the legacy `ProfileStore`; its `UserDefaults` body, favorite, candidate, and size-chart keys remain untouched. `RootView` normally opens `HomeView`. Existing model/fit/scan/store and manual UI tests remain in place.
- `Sources/BodyScan/` is the existing manually marked depth-assisted measurement flow; `Sources/AR/` is a garment ruler. Neither satisfies the new zero-measurement journey. Their behavior is intentionally unchanged.
- PR #5 is a separate experimental scanner, not a production replacement. Its depth acceptance counts the whole scene, not person-associated depth; the front/side sequence has no orientation-evidence gate. Permission completion can start a session after dismissal; tracking failure only updates copy. These are inspection findings, not device-tested results. Do not import it blindly.
- PR #6's production segments, requirements, architecture, stories, and initial prompts were reviewed. Conceptual schemas and diagrams are specifications, not proof of capture or rendering.
- PR #7 correctly isolates the new root and uses protected local metadata, but its original resolver conflated missing and incomplete profiles. A nonblank arbitrary asset string could unlock the saved route. Only ready profiles had parameter validation; unsupported schemas were decoded as the old payload first. The view performed synchronous disk access, had no injected state controller, no retry, no distinction between locked storage and damaged data, and no deletion confirmation.
- A temporary executable reproduced three defects before modification: malformed pending metadata saved successfully; an unknown asset resolved to `savedAvatar`; `{"schemaVersion":99,"newFormat":true}` was classified as corrupted rather than unsupported. None of the baseline tests caught these.

## Architecture and decisions

`Sources/AvatarNext/` is the isolated domain boundary, not a second scanner:

- `AvatarProfileRecord`: preserves PR #7's version-1 JSON fields (capture method/time, evidence status, optional asset identifier, derived normalized mesh controls). Validation applies to pending and reviewed records; rejects invalid dates, blank identifiers/keys, nonfinite/out-of-range controls, unsupported versions, and insufficient preview metadata.
- `AvatarEntryResolver`: pure decisions for missing, incomplete, invalid, preview-unavailable, and saved-avatar entry. Structurally eligible metadata is not a renderable avatar. `savedAvatar` additionally requires an explicit renderer compatibility check for that profile. The default rejects every renderer; Segment 0 has no approved asset/control mapping. Review status is not proof of scan accuracy or fit confidence.
- `AvatarProfilePersisting` / `AvatarProfileRepository`: injected async interface and serial actor. Disk I/O stays off the main actor. One repository instance should be shared by a future capture/profile owner; independently constructed actors are not a cross-process transaction coordinator.
- `AvatarPilotModel`: Debug-only main-actor presentation state. Handles refresh, retry, confirmed deletion outcome, and operation serialization. Known invalid/corrupt/unsupported data and transient I/O failure have distinct recovery. Storage failure does not become missing data or offer destructive corruption recovery.
- `AvatarPilotRootView`: Debug-only scrollable, Dynamic-Type-friendly metadata introduction and recovery. It does not request camera permission, show parameters, manufacture evidence, render an avatar, or offer a nonworking shopping action. Existing saved metadata can be removed only after confirmation.
- `AvatarExperienceFeatures`: requires the exact `-fitcheck-avatar-internal` launch argument and a Debug compilation. Release compiles out the pilot view, model, and root references; passing the argument cannot expose them.

No geometry estimator, generic asset fallback, renderer registry, backend, analytics, or catalog abstraction was added prematurely. Future derived geometry needs explicit provenance/unknown-region semantics and a reviewed schema change, not a reinterpretation of these mesh controls as validated measurements.

## Storage, migration, and privacy

- File: the app container's `Library/Application Support/fitcheck-avatar-profile.json`, preserving PR #7's path. No legacy defaults are read, migrated into an avatar, overwritten, or deleted.
- Save validates before mutation, encodes derived metadata only, writes a protected sibling staging file, excludes it from backup, then atomically publishes it using same-directory `rename(2)`. Invalid input or failed publication leaves the previous destination intact. Failed staging is removed; cleanup failures surface rather than reporting success.
- Complete iOS file protection is requested before publication. Backup exclusion applies per avatar file, not to the shared Application Support directory; valid previously saved v1 data receives backup exclusion on load. This does not revoke copies that might already exist in older backups.
- Load reads directly and returns missing only for actual file-not-found. It checks the schema header before decoding v1. Corrupt, invalid, and unsupported data are preserved until explicit deletion; no silent downgrade or fake success. Permission/locked-storage/disk errors remain I/O errors with retry.
- A private `.fitcheck-avatar-profile.pending` staging file is never loaded as a profile. Load, save, and deletion discard an interrupted unpublished save; errors surface if cleanup is blocked. File removal rejects unexpected directories rather than recursively deleting them. Delete is idempotent only for missing files. The UI never announces success before storage confirms it. Removal is logical deletion, not forensic erasure from flash or historical backups.
- No raw images, video, segmentation masks, depth maps, personal measurements, credentials, or sensitive logs were added. Derived shape metadata is still sensitive. There is no new network or external-service path.
- The legacy measurement UX remains visible by design until a separately reviewed replacement. This is not approval to ship it as the new zero-measurement consumer experience.
- No external code, model, asset, library, framework dependency, or paid service was selected. Standard Foundation/Combine/SwiftUI and the OS filesystem APIs suffice. No commercial 3D-asset licensing conclusion is made; future assets require individual code-versus-asset license and device-compatibility review.

## Verification

Environment: Xcode 26.5 (`17F42`), XcodeGen 2.46.0, iOS 26.5 simulator (`23F77`), x86_64 Mac. `xcrun devicectl list devices` reported the known physical iPhone unavailable. No real-device lock/unlock, LiDAR, or scan-accuracy validation was performed.

Completed baseline:

- `xcodegen generate` succeeded.
- `xcodebuild -project FitCheck.xcodeproj -scheme FitCheck -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/fitcheck-s0-main-derived CODE_SIGNING_ALLOWED=NO build -quiet` succeeded on main.
- PR #7 baseline full `test` succeeded: **54 passed, zero failed/skipped**, including the legacy manual UI journey. Result bundle: `/tmp/fitcheck-s0-pr7-baseline.xcresult`.
- A temporary executable against the real hardened repository and presentation model passed missing/incomplete/renderer-unavailable routing, replacement rejection preserving bytes, backup exclusion, future-schema preservation, and explicit corruption deletion/recovery. Synthetic fixtures only; no scanner input.
- The first hardened Debug suite passed **65 tests, zero failures/skips** (`/tmp/fitcheck-s0-hardened.xcresult`). Additional file-only deletion and interrupted-save coverage was added afterward.
- Production Release `build` without a testability override succeeded (`/tmp/fitcheck-s0-production-release`).
- An initial Release `build-for-testing` failed because production Release defaults disable `@testable import`. This is not an application compile defect; Release test runs require explicit `ENABLE_TESTABILITY=YES`. The production configuration was not weakened.
- A secondary iPhone 17e simulator stalled during initial data migration; its boot command timed out and the associated Release test attempt was cancelled. Do not interpret that attempt as a test pass.
- A subsequent 66-test run passed 65 and failed the legacy manual UI journey while waiting for its first field. Captured accessibility hierarchy showed the legacy home still visible after tapping the nested “My Body” text. The test now activates the containing navigation button (and explicitly clears launch arguments), preserving every input/result/relaunch/cancel/deletion assertion rather than masking the failure with retries or relaxed expectations.
- Binary inspection found the pilot view/model symbols, root identifier, and development label in the Debug runtime dylib, and none in the production Release executable. Xcode's Debug executable is a launcher stub; the actual Debug implementation is `FitCheck.debug.dylib`.
- After correcting semantic legacy navigation, the permanent Debug suite passed **67 tests, zero failures/skips** (`/tmp/fitcheck-s0-verified.xcresult`).
- A temporary real-UI deletion smoke initially exposed two assumptions: SwiftUI inherited the state group's identifier onto the delete control, and the system rendered `confirmationDialog` as a popover without a visible Cancel button. The smoke now activates the semantic control; deletion presentation was changed to an alert with explicit Cancel and Delete actions rather than relying on outside-tap dismissal.
- Final code, including explicit cancellation: **68 passed, zero failures/skips** (`/tmp/fitcheck-s0-complete.xcresult`): all 67 permanent tests plus one temporary actual-app smoke. That smoke cancelled deletion without changing the profile, confirmed deletion, then cold-launched back into onboarding. It was removed after proof; no fixture-generation path was added to the app.
- Release isolation: **2 passed, zero failures/skips** (`/tmp/fitcheck-s0-release-verified.xcresult`), exercising both the feature function and actual app launch with the internal argument. The app remained on the legacy home.
- Inspected actual simulator screenshots of missing-profile onboarding, incomplete metadata, and the final explicit Cancel/Delete alert. Retained synthetic-only visual proof outside Git: `/tmp/fitcheck-s0-onboarding.png`, `/tmp/fitcheck-s0-incomplete.png`, and `/tmp/fitcheck-s0-final-ui-proof/`. No real body or camera data was used.

Reproducible permanent-suite command (choose an installed destination and an unused result-bundle path):

```bash
xcodegen generate
xcodebuild -project FitCheck.xcodeproj -scheme FitCheck -configuration Debug \
  -destination 'platform=iOS Simulator,id=7F050083-C268-4F37-B730-C677F19A88EA' \
  -derivedDataPath /tmp/fitcheck-s0-hardened-derived \
  -resultBundlePath /tmp/fitcheck-s0-review.xcresult \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test -quiet
```

Release verification used the same project and simulator:

```bash
xcodebuild -project FitCheck.xcodeproj -scheme FitCheck -configuration Release \
  -destination 'platform=iOS Simulator,id=7F050083-C268-4F37-B730-C677F19A88EA' \
  -derivedDataPath /tmp/fitcheck-s0-release-derived \
  -resultBundlePath /tmp/fitcheck-s0-release-verified.xcresult \
  -parallel-testing-enabled NO \
  -only-testing:FitCheckTests/AvatarFeatureIsolationTests \
  -only-testing:FitCheckUITests/AvatarPilotUITests \
  ENABLE_TESTABILITY=YES CODE_SIGNING_ALLOWED=NO test -quiet
```

The separate production build used `-configuration Release -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/fitcheck-s0-production-release CODE_SIGNING_ALLOWED=NO build -quiet`, without `ENABLE_TESTABILITY`.

The new tests cover invalid metadata and schema guards, explicit routing, renderer compatibility, async persistence/replacement/deletion, preserved unknown/corrupt data, I/O failure/retry, deletion failure, per-file privacy attributes, old-data preservation, and actual app feature isolation.

Physical-device checks still required before relying on the storage policy with customer data: save/replace, lock/unlock and retry, cold launch, foreground refresh, backup policy, confirmed deletion, and protection on the oldest supported iOS version. Simulator tests cannot establish hardware encryption behavior.

## Gate decision

**Segment 0: GO for review as an isolated development foundation.** Xcode builds, permanent tests, actual deletion/cold-launch smoke, and Release isolation are verified. No merge was performed. **Not a production-release or scanning-feasibility GO:** physical data-protection checks, oldest-supported-iOS runtime coverage, real capture, assets, catalog, fit validation, and retailer authorization remain outstanding for their respective gates.

## Next segment boundary

Segment 1 requires a separately authorized task: harden draft PR #5's guided front/side capture lifecycle and person-aligned depth/orientation gating, then validate denial, interruption, cancel/retry, cropped/no-person, low-light, missing-depth, and distinct-view cases on an available LiDAR iPhone Pro. Keep buffers ephemeral. Do not add geometry estimation, avatar assets, garment rendering, or fit claims during that task.

Planning source: [production gates](https://github.com/anshbalusa-ui/itchathon/blob/docs/avatar-first-mvp-spec-and-stories-20261019/Docs/PRODUCTION_SEGMENTS.md). Completion of Segment 0 does not authorize production release or automatic work on later segments.
