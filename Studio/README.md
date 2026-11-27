# On You Studio

Local-first, desktop-browser T-shirt development workspace. Separate from the native **FitCheck** iOS module: no Node dependency is added to the shopper application.

## Install and launch

Use Node.js **22.12+ in the 22.x line** (implementation environment: 22.21.1) and npm. From the repository root:

```sh
cd Studio
npm ci
npm run dev
```

Open the printed localhost URL (normally `http://127.0.0.1:5173`). Use a current desktop Chrome, Edge, Firefox or Safari with IndexedDB and Web Crypto. 3D requires WebGL2; 2D, saving and project packages remain available when 3D is unsupported. Run on localhost or HTTPS, not by opening `index.html` as a file.

Production:

```sh
npm run typecheck
npm run build
npm run preview -- --port 4173
```

`dist/` is the deployable static application. No backend, account, credentials, analytics or body uploads. Dependencies are exact-version pinned with `package-lock.json`. Install only inside `Studio/`.

## Designer workflow

1. On **Projects**, name the project and garment. Select the maintained **Authored basic T-shirt** template, then **Create project**. Creation saves to this browser; a failure leaves a clearly unsaved draft available for retry.
2. The workspace displays the same garment revision in the **2D garment** illustration and the **3D preview**. Edit either name, choose a color swatch or custom color, and choose **Fit Model A** or **Fit Model B**. The models have different mesh coordinates, not just different labels.
3. Drag the 3D preview to orbit; use the wheel/trackpad to zoom. **Front**, **Side**, **Back** and **Reset** are real camera actions. Viewer keyboard instructions identify equivalent orbit/zoom controls. **2D + 3D**, **2D**, and **3D** change the workspace layout.
4. **Save project** (or Command/Ctrl-S) acknowledges a save only after IndexedDB commits. Garment appearance/name edits create a new immutable garment revision; model, layout and project-name changes keep garment identity. Unsaved state is explicit. Navigation offers save, discard, or keep editing.
5. Use **Projects** to reopen a saved project, **Switch project** when multiple projects exist, or **New project** to start another. A closed tab can be reopened through the saved project list on the same browser origin.
6. **Export package** downloads a self-contained `.onyou.json` file. Unsaved projects offer **Save & export**, and export stops if save fails. Save the download somewhere outside browser storage.
7. **Import project** opens a supported package after schema, reference and asset checks. It creates a **separate project**, preserves its immutable garment revisions and appearance/model selection, and records its source project identity. Import never overwrites an existing project, even when the package came from this same browser.

## Storage and recovery

Projects, immutable garment revisions and referenced mesh bytes are transactionally stored in IndexedDB. A failed write leaves the previous acknowledged record intact. Concurrent changes from another tab are rejected rather than silently overwriting newer work; reopen the project before continuing from that newer save. No in-memory fallback is presented as a durable save.

Storage belongs to the exact browser profile and origin (scheme, host and port). Development port 5173 and preview port 4173 have separate stores. Private browsing, clearing site data, storage eviction or loss of the browser profile may remove it. **Browser-local storage is not a permanent backup or an encrypted vault.** Other people/software with access to the profile may access these records. Use exported packages as backups and treat them as design files.

The app requests persistent/durable storage after a successful save where supported, with a manual request control on the footer. A grant reduces automatic eviction risk; it does not protect against clearing data or hardware loss. No cloud sync is implied.

An import error does not change the open or saved project. A storage error leaves edits unsaved and offers the existing Save action for retry. If the preview assets fail to load, use **Retry loading assets**. Unsupported 3D does not block 2D editing or portability.

## Supported representation and limits

- One maintained T-shirt template; project/garment names and visual color.
- Numeric SVG outline and actual indexed Three.js meshes; two standardized authored, nonpersonal fitting references with base shorts.
- Canonical right-handed geometry, Y-up, meters, front toward +Z; exact source transforms and hashes.
- Version 1 `GarmentProject`, `GarmentRevision`, `MeshAssetDescriptor`, `FitModelRevision` schemas in `Shared/Contracts/`, consumed at application boundaries.
- Packages contain metadata, revision lineage, both reference models, template, all six permitted mesh assets and licensing/provenance. Supported package limit: 12 MiB; 3 MiB per mesh payload; 100 garment revisions. Unknown schema versions, external-resource fields, unsupported units/formats and modified catalog assets are rejected, not silently repaired.
- This importer accepts **only this maintained catalog**, not arbitrary GLB/SVG/model files. Source URLs in provenance are inert metadata and are never fetched from a package.

**Illustrative preview only.** The 2D outline is not a cutting pattern. The shirt is an authored shell adapted separately to each reference model; switching models is not garment sizing or cloth draping. Color is a visual material property, not textile mechanics. No personal likeness, demographic percentile, physical cloth simulation, collision guarantee, pressure/tension, sizing recommendation or manufacturing validation. There is no CAD/DXF/tech-pack export, pattern editing, points of measure or grading in Goal 2.

## Asset rights and reproducibility

Source: the existing `DevelopmentAssets/HumanShowcase/human-showcase-v1.bin` and its `NOTICE.txt` / `LICENSE.txt`. The original MakeHuman **asset** and adapted body are CC0 1.0; the repository's authored shirt/shorts/converter are also CC0. No MakeHuman AGPL software, restricted statistical body model, personal scan or new dataset is imported.

`Studio/public/assets/NOTICE.txt` identifies source hashes, conversions and authored variants. `LICENSE.txt` accompanies the public assets. The source payload remains unchanged. Browser assets are committed, so Python is unnecessary to run the app. To reproducibly regenerate them from the pinned source using Python 3:

```sh
npm run assets
```

The converter is under `Studio/scripts/`; it does not replace or modify the native pipeline. Descriptor transforms capture the authored affine changes and normal conversion. These authored proportions establish no measured-human accuracy.

## Focused verification

```sh
npm run typecheck
npm run build
npm test
npx playwright install chromium
npm run test:browser
```

The browser cases run against the production preview, actual WebGL geometry, downloads and IndexedDB. They cover creation, camera/model/color changes, close/reopen, export/import, invalid packages, a deliberately failed browser write with previous-save recovery, navigation and unsupported WebGL. Fault injection is only used to produce errors; success is not mocked. Browser pixel differences establish rendered changes, not accuracy or physical fit.

See [`Docs/ONYOU_STUDIO_FOUNDATION.md`](../Docs/ONYOU_STUDIO_FOUNDATION.md) for the actual verification receipt, branch dependency, architecture boundaries and exact Goal 3 work. Goal 1 native tests are not Studio evidence.
