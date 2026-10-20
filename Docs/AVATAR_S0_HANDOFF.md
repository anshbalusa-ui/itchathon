# Segment 0: isolated avatar-first foundation (unverified)

This branch begins the commercial FitCheck work without replacing the working manual-demo app. It intentionally **does not capture a body, produce a mesh, verify a fit, or connect a retailer**.

## What changed

- `Sources/AvatarNext/AvatarProfileRecord.swift`: a versioned, derived-parameter-only profile contract, explicit review status, and pure route resolver. It does **not** store raw camera imagery or claim fit accuracy.
- `Sources/AvatarNext/AvatarProfileRepository.swift`: atomic local JSON save/load/delete with complete iOS file protection and explicit invalid/corrupt/unsupported schema errors.
- `Sources/AvatarNext/AvatarPilotRootView.swift`: an honest, internal-only avatar onboarding/progress and recovery screen. It does not request camera permission, show fake captured bodies or claim an avatar was created.
- `Sources/Views/RootView.swift`: preserves the existing `HomeView()` by default. In a DEBUG build only, app launch argument `-fitcheck-avatar-internal` shows the isolated pilot shell.
- `Tests/AvatarFoundationTests.swift`: missing/incomplete/invalid routes; derived-profile save/load/delete; corrupt/unsupported profile guards; rejection of fake "ready" evidence.

**Note:** `usableForIllustrativePreview` is *not* approval for fit inference. It only indicates a derived profile has passed a later avatar-specific review stage. No production path creates that status in this branch.

## Reviewer verification (Mac required)

1. Install a compatible Xcode toolchain and XcodeGen; check the project's current iOS deployment target and installed simulators.
2. `xcodegen generate`
3. `xcodebuild -project FitCheck.xcodeproj -scheme FitCheck -showdestinations`
4. Run unit/UI tests on an installed simulator and record exact results. Example, adjust simulator name as needed:

```bash
xcodebuild -project FitCheck.xcodeproj -scheme FitCheck -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO test
```

5. Run/debug normally: the old FitCheck HomeView must open with no changed measurement behavior.
6. In Xcode Scheme -> Run -> Arguments Passed On Launch, add `-fitcheck-avatar-internal`, run a DEBUG build and confirm the new screen explicitly says scanning is not yet available.
7. Without flag, and in Release builds, the old app must still open. Neither simulator nor an unsupported iPhone proves scanner accuracy.
8. Verify deleting derived avatar metadata does not remove the existing manual body/garment data; test local storage path and file protection behavior on iPhone.

## Gate status

**S0: NO-GO / awaiting validation.** The source is committed, but this authoring environment does not include Apple's Xcode or a LiDAR iPhone session. No successful Xcode build, iOS UI test or real-device scan is claimed. Resolve any iOS compiler issues before approving or merging.

Only once Segment 0 builds cleanly and PR #5 is reviewed should Segment 1 begin depth-person alignment and guided physical capture. Refer to [commercial segment plan](https://github.com/anshbalusa-ui/itchathon/blob/docs/avatar-first-mvp-spec-and-stories-20261019/Docs/PRODUCTION_SEGMENTS.md) and [kickoff prompt](https://github.com/anshbalusa-ui/itchathon/blob/docs/avatar-first-mvp-spec-and-stories-20261019/Docs/PRODUCTION_KICKOFF_PROMPT.md).
