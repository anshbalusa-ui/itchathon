# On You Studio — Goal 2 foundation

**Implementation record, 2026-11-26.** Brand-side desktop-browser workspace, independent of personal scanning. An illustrative garment preview is not physical cloth simulation or manufacturing validation. Native product **On You**, module/scheme **FitCheck**, remains separate.

## Starting repository state and protection

Fetched all origin branches and inspected open, merged and recently updated PRs before editing. Compared actual branch trees, recent author commits and foundation/hardening diffs, not just titles. No `Studio/`, `Shared/Contracts/`, frontend package manifest or newer Studio branch existed on any remote branch at refresh.

| Ref / review | Refreshed SHA | Disposition |
| --- | --- | --- |
| `main` | `b3e0397eb6ac1ce8ab13b84e00a645e1a49a6e8c` | Latest main remains Aashutosh's stationary body/garment scan work; ancestor of chosen foundation |
| PR #30, `integration/onyou-foundation-20261122` | `075db5abdaef95a0ae0fd9adee67c8bee16b1f7f` | Open draft against main; chosen base |
| PR #31, `feature/onyou-consumer-scan-hardening` | `4a8efc362e89995cf898e2945fa83ae547200dca` | Open draft against foundation; separate completed Goal 1 workstream, not copied |
| PR #29, `feature/onyou-stationary-scan-refinement` | `45b5db23c53fc38198ee043d950881f40766f100` | Open draft; existing consolidated scanner changes retained |
| PR #28, `review/onyou-release-readiness-20261110` | `16dccd39162dfcb3519d3cfc8f7211446b6d5b24` | Open draft; untouched |
| PRs #25, #26, #27 | Existing merged consumer implementations | Retained through the foundation ancestry |

The supplied working directory had no existing checkout. Cloned the repository without touching other user directories, then created an isolated `onyou-studio` worktree and previously nonexistent `feature/onyou-studio-foundation` branch from the remote foundation. No reset, stash, force-push, source replacement, native cherry-pick, automatic merge or teammate-PR closure. Existing uncommitted work in other checkouts was not imported or overwritten.

The Studio draft PR depends on **PR #30**, not PR #31. Its review base is `integration/onyou-foundation-20261122` while that foundation is unmerged. Consumer hardening can merge independently; Studio adds no scanner dependency.

## Existing work reused, not rebuilt

Read the consolidation, platform architecture, execution roadmap and Goal 1 hardening handoff (the latter directly from PR #31's branch; not copied into this worktree). Read the existing human asset notices/converter/decoder, `RendererMesh`, `BodyModelGenerator`, `BodyShapeKernel`, `MeasurementAvatarGeometry`, `GarmentPatternEvidence` and `TryOnGarmentShell` boundaries.

- Reuse the **existing CC0 human, shirt and shorts geometry** through an offline browser adapter. The source payload, original converter and all native implementations stay unchanged.
- Reuse immutable mesh/hash/unit/provenance semantics, not a second JavaScript implementation of the Swift body-shaping engine.
- Preserve the distinction between flat shirt width, circumference, image landmarks and actual sewing patterns. None is silently relabelled as manufacturing data.
- Leave Aashu's scanner, saved scans, closet, native try-on, optional manual illustration and Goal 1 coordinator work alone. No native storage-format migration or Node dependency enters iOS.
- Eternal is a motivating founder use case for the example project-name hint, **not customer-validation evidence**. No claim that designers have validated the workflow or eliminated samples.

## Modules and actual workflows

| Module | Responsibility |
| --- | --- |
| `Studio/src/App.tsx` | Project home, create/open/import, project switching, editable names/color/model/layout, unsaved navigation, save/export and honest status/errors |
| `Studio/src/components/GarmentDrawing.tsx` | Numeric revision-backed SVG front illustration; no external SVG execution or cutting-pattern claim |
| `Studio/src/components/GarmentViewer.tsx` | Three.js scene lifetime, model/material updates, orbit/zoom/presets/keyboard, loading/unsupported/context-loss states |
| `Studio/src/rendering/preview.ts` | Validated canonical mesh to disposable Three.js BufferGeometry adapter |
| `Studio/src/domain/types.ts` | Minimal platform-neutral domain records and application payload types |
| `Studio/src/domain/validation.ts` | Runtime JSON Schema admission, catalog/reference/lineage checks and bounded mesh/hash validation |
| `Studio/src/domain/projects.ts` | Project creation, draft application, immutable garment revisions and safe import copies |
| `Studio/src/domain/repository.ts` | Atomic IndexedDB persistence, list/open, optimistic concurrent-save protection and explicit failures |
| `Studio/src/domain/packages.ts` | Size-bounded portable JSON package import/export |
| `Studio/src/domain/library.ts` | Bounded fixed-origin catalog/UUID asset loading; imported packages cannot cause external asset fetches |
| `Studio/scripts/build_assets.py` | Deterministic pinned-source conversion, authored variant, source transforms, hashes and notices |
| `Shared/Contracts/` | Versioned schemas and canonical examples consumed by Studio; no iOS or speculative solver DTOs |

A designer creates a named T-shirt project, sees the actual 2D/3D template, chooses between genuinely different reference models, changes appearance, saves locally, closes/reopens, exports and imports a separate copy with the same garment revision and supported appearance/model selection. Primary actions are implemented; there are no fake dimension sliders, upload controls or simulation buttons.

The desktop-first workspace separates project/garment controls from the garment canvas. Split/2D/3D views, keyboard-native form controls, labelled camera actions, visible unsaved state, native modal focus containment, a skip link and smaller-window layouts support navigation. There is no claim of a formal accessibility certification.

## Geometry, rights and coordinate conventions

Source payload: `DevelopmentAssets/HumanShowcase/human-showcase-v1.bin`, SHA-256 **`6977bd1aeba54c9f4ef82f9d7f9b8b996d030b2758e226b61dcb9fbccfe4f6e9`**. This is the repository's existing `FCHUMAN1` body/shirt/vest/shorts data. Studio uses body, shirt and shorts, not the unused vest.

Verified the [immutable upstream OBJ header](https://raw.githubusercontent.com/makehumancommunity/makehuman2/3ef8a20dfec873fdf84d3315aeaf98694cad91bf/data/base/hm08/base.obj), which explicitly releases the asset as CC0 in September 2020, and the [CC0 asset terms](https://raw.githubusercontent.com/makehumancommunity/makehuman/master/LICENSE.ASSETS.md). Original OBJ hash: `9e8e529a386823fa0af5aa0cf4f082076f24f0f1a1a904003b2ab2b57b911342`. The repository's authored shirt/shorts surfaces are also CC0 under the existing notice. No AGPL MakeHuman software or restricted body dataset/model is used.

The offline converter preserves the pinned source and generates six indexed mesh JSON assets: body, shorts and shirt for each fitting reference. Asset descriptions pin exact UTF-8 SHA-256, byte length, vertex/index counts, UInt32-little-endian index topology hash, bounds, producer, version and licensing. Catalog metadata, generated notices and exported package provenance include the source hash and upstream attribution.

| Variant | Geometry | Meaning |
| --- | --- | --- |
| Fit Model A | Existing 1.80 m authored source coordinates | Nonpersonal reference, not a percentile |
| Fit Model B | X ×1.12, Y ×0.95, Z ×1.08 around Z=0.055 m; 1.71 m high | Deliberately distinct authored proportions, not an accuracy claim or a garment size |

Both have the same source topology but different coordinate bytes and hashes. The affine transform applies consistently to body, modest opaque shorts and authored shirt. Normals use the inverse transpose and are normalized. Positive determinant preserves triangle winding. `sourceToCanonical` declares the shared source frame and exact column-major matrix; it does not pretend the original OBJ was already in meters. The repository's earlier pinned conversion established the normalized 1.80 m source payload. Studio starts from that payload, not an uncalibrated OBJ.

Canonical geometry is **right-handed, Y-up, meters, front toward +Z**, counter-clockwise indexed triangles. The frontal camera looks from +Z toward the scene. Full-body camera presets and bounded zoom/orbit operate on actual selected geometry. The renderer creates its context/scene once per mounted viewer; model changes replace and dispose buffers, color changes update material, and frames render on demand. There are no asynchronous per-model loads that can publish stale geometry. Context loss is surfaced. Unmount disposes controls, geometry, materials, renderer and observers.

The template has stable identity/version, source/license, a numeric 2D outline and per-reference 3D preview assets. Both views refer to the current garment revision. Model selection does not manufacture a new garment size or rewrite the garment revision. The 2D outline is an authored **illustration**, not flattened sewing pieces. The 3D shirt remains a body-adapted authored shell with no fabric/seam/contact solver.

## Contracts, storage and portability

The four requested version-1 records are produced and consumed, rather than added as unused schemas:

- **GarmentProject:** UUID project identity, independent saved project revision token/parent, timestamps, producer, current garment revision, selected fitting model and view. Imports record their original project/revision identity.
- **GarmentRevision:** immutable garment/revision identity and parent, template version, names, visual material, 2D representation, associated model-specific preview assets and source/illustrative status. Garment identity is independent of the container project.
- **MeshAssetDescriptor:** format/topology version, content and topology hashes, resource counts, units/basis/front, source transform, bounds, license and illustrative provenance.
- **FitModelRevision:** stable nonpersonal model/revision identity, licensed body/base-garment references, authored pose, authored-bounds height and illustrative validation status.

Visual material contains only color, not guessed textile mechanics. Unknown schema versions, formats, units, fields or catalog references are rejected. Schemas are strict about required and extra properties. Rendering consumes admitted assets and checks selected references; persistence and import validate the complete package.

IndexedDB acknowledges a save only on transaction completion. The complete package, including asset bytes and immutable garment revisions, is persisted atomically. The previous acknowledged record survives failed transactions. A project revision token detects concurrent-tab saves inside the write transaction; stale work cannot silently replace newer data. No successful save is fabricated in memory. Persistent storage is requested where available, but browser clearing, eviction, profile loss and hardware failure remain possible. Browser-local storage is neither a permanent backup nor a private encrypted vault.

A `.onyou.json` package is a self-contained supported-project snapshot, not a CAD/tech-pack file. It includes both fitting references, all six CC0 geometry assets, immutable garment revision chain, template, exact hashes, source/license data and preview limitations. Bundling both models preserves the ability to switch references after reopening. Import verifies required fields, lineage, exact supported catalog metadata, asset hashes and numerical structure before saving a **new** project ID. Garment revision identities and data are preserved exactly; unrelated saved projects are never overwritten.

Input is limited to 12 MiB per package, 3 MiB per mesh payload and 100 garment revisions. Only the maintained catalog is admitted; arbitrary SVG, shader, scripts, URLs, third-party GLB or modified catalog meshes are unsupported. Metadata URLs are inert. No imported resource causes network loading. This restrictive v1 importer is an intentional safety/compatibility boundary, not generic asset ingestion.

## Verification receipt

Actual checks on macOS x64, Node **22.21.1**, npm **10.9.4**, with pinned dependencies installed from the lockfile. The Node distribution checksum was verified against the official release manifest.

| Check | Actual result |
| --- | --- |
| `npm ci --ignore-scripts --no-fund --no-audit` | Passed; exact lockfile installation |
| `npm test` | **12 passed**, 0 failed/skipped; domain contracts, canonical examples, geometry/normal transforms, immutable revision lineage, IndexedDB roundtrip/conflicts/aborts and import forks |
| `npm run typecheck` | Passed after the final code/test edits |
| `npm run build` | Passed; production assets emitted in about 3 seconds |
| `CI= npm run test:browser` | **6 passed** against the production preview in 36.3 seconds |
| `npm run dev -- --port 5173 --strictPort` | Actual Vite development server launched successfully |
| Browser inspection | Actual project home and rendered workspace inspected; Model B and Moss appeared in both views; acknowledged save, full-body camera framing and no page JavaScript errors observed |

Browser cases exercise actual WebGL rendering, actual IndexedDB and actual downloaded/reimported files, not mocked success responses:

1. Create/name a project and garment; inspect the SVG and full-body canvas; switch A/B and verify different rendered pixels and unchanged canvas identity; change color in both views; orbit/zoom/presets/keyboard; save; close the tab; reopen; export and import the package. Immutable garment revisions and exact asset bytes survive, while the imported project receives a new container identity.
2. Reject unsupported version, altered payload hash, external-resource fields and an oversized package without overwriting the saved project or requesting external assets.
3. Deliberately fail the next native IndexedDB write with a quota exception, retain unsaved UI state, reload and recover the previous acknowledged save, then successfully retry.
4. Exercise unsaved navigation with Escape/save-and-continue, another project, project switching and 2D/3D layout at **1000×900**, with no horizontal page overflow.
5. Deny WebGL context creation deliberately; show explicit unsupported rendering while real 2D editing, saving and exporting continue.
6. Fail initial creation's write, keep the draft editable, change its name and save/reopen it successfully.

The main browser workflow also runs at **1440×1000**. Separate interactive inspection used a **1365×768** browser viewport. Its screenshots are observations of the real application, not substitutes for geometry or persistence. Automated evidence is reproducible from `Studio/tests/workspace.spec.ts`; Playwright writes ignored screenshots/traces under `Studio/test-results/`.

Demonstrated issues fixed before the final browser run: the initial controls target was not applied to the camera until interaction (clipped head), and an implicit model label did not resolve unambiguously for exact-label automation. Admission originally treated smoothed shading normals as face normals; this incorrectly rejected the pinned source at tight folds. It now verifies finite unit normals, nondegenerate triangles, actual shared-edge orientation/manifold limits and pinned topology/content hashes, preserving the existing source rather than flipping its faces. A mutation-injection test fixture was isolated from its expected baseline.

Nonblocking build warning: the current eager application chunk is about **915 kB / 254 kB gzip**, including Three.js and runtime schema validation. Its chunk-size warning is not suppressed. Code splitting is a delivery optimization, not missing product behavior. The six mesh payloads total **4,877,656 bytes**. The current importer deliberately supports only the maintained v1 catalog.

Verification limits: Chromium was exercised, including software WebGL in automated runs; Safari, Firefox, mobile layouts, hardware-specific GPUs, formal accessibility certification, real disk exhaustion and physical fit/manufacturing accuracy are unverified. Quota/WebGL failures were explicitly injected to test recovery, not supplied as successful fallbacks. No unrelated native iOS tests, device scans or historical PR #31 cases were rerun or counted as Studio evidence.

## Goal 3 prerequisites and exact next scope

Keep this workspace/repository/viewer. Do **not** rebuild them or connect the consumer scanner to authoring.

1. Agree T-shirt endpoint definitions and a supported pattern/template subset with an independent designer. Eternal's experience motivates this step; it does not replace it.
2. Add revisioned front/back/sleeve/neckband pieces with stable curve/edge IDs, meter units, seam correspondences, grain/fold/cut information, notches and explicit seam allowance semantics.
3. Add named points of measure, endpoint definitions, tolerances and editable finished-garment dimensions. Keep flat half-chest distinct from circumference and body recommendations.
4. Add base-size identity, named sizes and explicit per-POM/per-piece grade rules or values. Uniformly scaling this mannequin or shell is not size grading.
5. Replace the authored preview adapter with dimension-driven 2D/3D geometry that changes the intended dimensions without silently changing unrelated ones. Version the template/topology; retain old revisions and migration compatibility.
6. Add real revision/size comparison and restore-as-new-revision behavior. Extend the package schema and canonical examples; reject incompatible old/new patterns explicitly.
7. Implement only supported specification exports (e.g. revision/units/POM/tolerance CSV/JSON and an explicitly supported vector subset). DXF/PDF/tech-pack support requires actual exporters and loss/readiness disclosures.
8. Keep a future validated simulation result behind the geometry adapter, keyed to immutable garment/model/material revisions with explicit status. No solver or fake simulation record is needed for Goal 3.

Goal 4 statistical completion remains an independent licensed research track. No consumer body scans, uploads, training dataset, inferred capture acceptance or restricted model installation is introduced. Physical samples, sizing accuracy and textile validation remain future evidence gates, not claims supplied by this foundation.
