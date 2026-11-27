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

1. On **Projects**, name the project and garment, select **Parametric short-sleeve T-shirt · v2**, then **Create project**. Creation saves locally; failed storage leaves a retryable unsaved draft. The v1 illustration remains available for compatibility.
2. In **Measurements**, select a size and **cm** or **in**. Edit body length, flat chest/hem width, shoulder width, sleeve length/opening, or neck width/depth. Focus a measurement to inspect its actual construction-piece diagram. Body length and chest width also have keyboard-accessible drag handles. Invalid values keep the last valid geometry visible and block saving until corrected or discarded.
3. Choose front/back technical flats, all five construction pieces, or an individual piece. Toggle seam allowances, grainlines and notches; zoom/pan or **Fit drawing**. Solid lines are finished seam boundaries; outer dashed lines are cutting boundaries. This sheet is not a fabric marker.
4. **Size chart & grading** adds your own size labels, edits each size, selects the base size, and sets independent per-measurement deltas from that base. Zero length grading stays zero when chest grading changes. Unsupported construction identifies the affected size instead of silently skipping it.
5. The existing 3D controls orbit/zoom and select **Front**, **Side**, **Back**, or **Reset**. **Fit Model A/B** replace the actual reference body, not the garment size. Dimension-driven garment buffers are regenerated separately from the body. This is an illustrative proportion preview, not draping or collision validation.
6. **Save project** (Command/Ctrl-S) acknowledges IndexedDB commit before reporting success. Design, specification and grade changes append immutable garment revisions. Project name, fitting model, unit, selected size and view settings do not create garment revisions.
7. **Compare & history** compares sizes or saved revisions through measurement/size-chart differences, meter-based pattern overlays and a wireframe garment in the same 3D camera. Restore appends a new revision; historical records are unchanged. Legacy designs have no historical POMs: use their explicit upgrade action to start authored defaults while preserving the original revision.
8. **Projects**, **Switch project**, and **New project** retain the existing unsaved-change guard. Reopen a saved project on the same browser origin to recover specifications, sizes, rules, revision history, model and preview selections.
9. **Specification exports** saves the valid draft first, then downloads CSV for all sizes, structured JSON, or the selected size's SVG pattern sheet with explicit millimeter dimensions and a 1:1 viewBox. SVG screen zoom does not affect exported coordinates. These are preliminary specifications, not factory-approved cutting files.
10. **Export package** downloads a self-contained `.onyou.json` backup including the complete supported editable history and permitted assets. **Import project** validates and creates a separate project; it never overwrites an unrelated project. V1 packages remain supported without inventing historical measurements.

## Storage and recovery

Projects, immutable garment revisions and referenced mesh bytes are transactionally stored in IndexedDB. A failed write leaves the previous acknowledged record intact. Concurrent changes from another tab are rejected rather than silently overwriting newer work; reopen the project before continuing from that newer save. No in-memory fallback is presented as a durable save.

Storage belongs to the exact browser profile and origin (scheme, host and port). Development port 5173 and preview port 4173 have separate stores. Private browsing, clearing site data, storage eviction or loss of the browser profile may remove it. **Browser-local storage is not a permanent backup or an encrypted vault.** Other people/software with access to the profile may access these records. Use exported packages as backups and treat them as design files.

The app requests persistent/durable storage after a successful save where supported, with a manual request control on the footer. A grant reduces automatic eviction risk; it does not protect against clearing data or hardware loss. No cloud sync is implied.

An import error does not change the open or saved project. A storage error leaves edits unsaved and offers the existing Save action for retry. If the preview assets fail to load, use **Retry loading assets**. Unsupported 3D does not block 2D editing or portability.

## Supported representation and limits

- A bounded, provisional short-sleeve T-shirt construction: full front/back body panels, two handed sleeves and a folded neckband; stable point/edge/piece/seam identities, grain, notches, material groups and cut quantities.
- Eight independent garment POMs in canonical meters; cm/in display and optional tolerances; up to eight named sizes with explicit star-from-base grade rules, not mannequin scaling.
- Deterministic line/cubic patterns; closed/simple polygon, seam-length, endpoint and offset validation. Ten-millimeter miter allowances apply to the sampled seam boundary (maximum 0.5 mm curve approximation); these are not production hem/stitch instructions.
- Indexed dimension-driven Three.js garments with actual surface-bound POM endpoints/paths. Reference models retain their licensed original geometry. Right-handed, Y-up, meters, front +Z.
- Consumed V1/V2 project/revision schemas and `GarmentSpecification`, `PatternDefinition`, `SizeSet`, `GradeRule` schemas/examples in `Shared/Contracts/`. V1 immutable records and mesh hashes remain unchanged.
- Packages retain the original six catalog assets once and compact generated patterns/specifications, not one mesh payload per size/edit. Limits remain 12 MiB per package, 3 MiB per mesh, 100 garment revisions, and eight sizes; the byte limit may be reached before those count limits.
- Only maintained template/generator versions and catalog assets are accepted. No arbitrary GLB/SVG/CAD import, imported scripts or network resource loading. Unsupported versions, modified geometry, inconsistent grades and bad hashes are rejected.

**Provisional, not manufacturing approved.** The construction has not received designer/toile approval. Shoulder slope, chest-line placement, cap ease and neckband stretch are authored assumptions, not fabric measurements. The non-isometric 3D mapping preserves the supported POM definitions but does not preserve every seam's spatial length or solve cloth contact. Some valid 2D constructions cannot be positioned in the supported preview pose and produce an explicit preview error without resizing the garment. Model intersections, fit, material response and physical grading remain unverified. No consumer body measurements, personal scans, pressure/tension, fit recommendations, DXF/AAMA/ASTM, tech packs, nesting or factory-readiness claims.

## Asset rights and reproducibility

Source: the existing `DevelopmentAssets/HumanShowcase/human-showcase-v1.bin` and its `NOTICE.txt` / `LICENSE.txt`. The original MakeHuman **asset** and adapted body are CC0 1.0; the repository's authored shirt/shorts/converter are also CC0. No MakeHuman AGPL software, restricted statistical body model, personal scan or new dataset is imported.

`Studio/public/assets/NOTICE.txt` identifies source hashes, conversions and authored variants. `LICENSE.txt` accompanies the public assets. The source payload remains unchanged. Browser assets are committed, so Python is unnecessary to run the app. To reproducibly regenerate them from the pinned source using Python 3:

```sh
npm run assets
```

The converter is under `Studio/scripts/`; it does not replace or modify the native pipeline. Descriptor transforms capture the authored affine changes and normal conversion. These authored proportions establish no measured-human accuracy.

The new `src/patterns/template.json` is an original CC0 provisional construction, with a pinned source hash and generator version. This source license does not relicense a designer's project. Generated pattern/spec records preserve provenance; derived preview meshes are safely regenerated by the maintained adapter. No new third-party body assets or statistical datasets are added.

## Focused verification

```sh
npm run typecheck
npm run build
npm test
npx playwright install chromium
npm run test:browser
```

The focused cases cover legacy regressions plus numerical POM isolation, seam correspondence, actual allowances, unit conversion, grading, V1 upgrade, append-only restoration, import integrity and failure recovery. Browser journeys use the production app, actual WebGL geometry, downloads and IndexedDB; only failures are injected, not successful saves. Pixel changes are rendering evidence, not physical accuracy.

See [`Docs/ONYOU_STUDIO_GARMENT_DEVELOPMENT.md`](../Docs/ONYOU_STUDIO_GARMENT_DEVELOPMENT.md) for construction equations, provisional assumptions, migration/export semantics and the actual Goal 3 verification receipt. The historical [Goal 2 receipt](../Docs/ONYOU_STUDIO_FOUNDATION.md) is retained; native Goal 1 tests are not Studio evidence.
