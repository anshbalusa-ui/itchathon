# On You

An offline iPhone tool for entering body measurements and exploring a matching 3D approximation.

## Run

```sh
bitrig preview -platform iOS
```

`Project.json` is the build configuration. The app is named **On You**; its internal Swift module remains `FitCheck` for compatibility with the imported tests.

## Screens

- **Body:** drag to orbit, pinch to zoom, select Front / Side / Back, or open full screen.
- **Measurements:** enter height, chest, waist, hips, and shoulder width in centimeters or inches. The preview updates while editing. Save applies the measurements to the main body.
- **History:** inspect saved bodies, compare dimensions with the current body, restore a version, or delete a record without changing the current body.
- **How to measure:** instructions for each dimension.
- **About:** mesh display option, model source, and local data information.

Measurements and history use the separate `on-you.measurements.v1` local storage namespace. Existing FitCheck records are untouched. No account, server, runtime model download, or added package is required.

## Model

The bundled anatomical mesh comes from [MakeHuman](https://github.com/makehumancommunity/makehuman), under CC0. Original provenance and licenses remain in `DevelopmentAssets/HumanShowcase/`. Chest, waist, and hip scale factors come from convex cross-sections of the actual base mesh. Smooth regional deformation changes vertex positions; normals are rebuilt for the new surface. Height and shoulder width also affect geometry. SceneKit supplies native rendering, lighting, orbit, and zoom.

This is an approximate body shape from five dimensions. It does not uniquely reconstruct a person or simulate clothing fit. Shoulders use an approximate anatomical reference; unentered proportions are estimated.

[humanoid-kit](https://github.com/jbcom/humanoid-kit) was also reviewed: its web runtime and large morph system were unnecessary for this native MVP. No humanoid-kit software was copied. We reused the CC0 MakeHuman mesh already supplied by the requested itchathon repository.

## Verification

New tests: `Tests/OnYouTests.swift` checks section dimensions, height, normals, invalid inputs, extreme values, history, persistence, and corrupted-storage handling. `UITests/OnYouUITests.swift` covers measurement entry, saving, and history navigation.

Bitrig currently rejects `test` for standard `Project.json` projects (exit 78). For this workspace, tests are run against a temporary XcodeGen project with the same JSON specification, using Xcode's command-line test runner. App builds and previews use Bitrig.

Verified on November 6, 2026: five On You unit tests and one measurement-entry/save/history UI test passed on the iPhone 17 simulator. Debug and Release builds passed through Bitrig. The preview rendered the model, front/side controls, full-screen presentation, and drag rotation on iPhone 18 Pro Max. Physical-device measurement accuracy has not been checked.

## Upstream

Imported from [anshbalusa-ui/itchathon](https://github.com/anshbalusa-ui/itchathon), commit `40feaf4931614637c3e1dc05407af2660eb56f19`. The [upstream README](Docs/UPSTREAM_README.md) and original development labs remain for reference. Debug-only `-fitcheck-…` launch flags retain their original internal routes; normal Debug and Release launch On You.
