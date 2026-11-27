# On You Studio — garment development (Goal 3)

Implementation record, 2026-11-27. This extends the existing Studio, not the native consumer application. Authored garment geometry, numerical seam consistency and a successful export do not establish physical fit or production cutting approval.

## Starting repository state

Refreshed all remote branches, recent author commits and open/merged PRs; inspected the actual Studio-bearing branch contents. No newer Studio or Goal 3 implementation existed at refresh. The existing Studio worktree was clean.

| Ref / PR | Refreshed head | State and role |
| --- | --- | --- |
| `main` | `b3e0397eb6ac1ce8ab13b84e00a645e1a49a6e8c` | Aashutosh's existing stationary scanner; untouched |
| #30 `integration/onyou-foundation-20261122` | `075db5abdaef95a0ae0fd9adee67c8bee16b1f7f` | Open draft foundation dependency |
| #31 `feature/onyou-consumer-scan-hardening` | `4a8efc362e89995cf898e2945fa83ae547200dca` | Open draft, independent consumer track; not copied |
| #32 `feature/onyou-studio-foundation` | `3c8f6808d0c5a5b13e49cfbf3f08253eba39cd3f` | Open draft; immediate Goal 3 base |

Created a new `feature/onyou-studio-garment-development` branch and isolated worktree from #32's reviewed head. No reset, stash, force-push, teammate overwrite, automatic merge or PR closure. The new draft review must be stacked against `feature/onyou-studio-foundation` while #32 is unmerged, not old main or consumer-hardening #31.

## Goal 2 functionality preserved

The existing React/TypeScript/Vite application, project home/navigation, local catalog loader, licensed model assets, IndexedDB project/summary stores, atomic acknowledgements, optimistic project revision tokens, immutable garment history, bounded package IO, source hashes and original rendering controls are retained.

- Version-1 schemas and immutable historical records keep their original meanings. An authored outline is not retroactively a sewing pattern and has no invented measurements.
- An explicit upgrade starts a new parametric garment revision from labelled authored defaults, retaining the original design and assets.
- The existing Three.js scene and camera remain mount-owned. Model buffers change only with the fitting model; garment and comparison buffers have separate update/disposal paths. There is one camera for both compared garments.
- The original `Studio/public/assets/` and `DevelopmentAssets/HumanShowcase/` geometry/provenance are not regenerated or rewritten. CC0 reference models are nonpersonal, not percentiles or body ideals.
- No changes to native scanner, shopper onboarding, saved scans, closet, iOS geometry, native storage or Xcode settings. No Node dependency enters the native application.

Ben's finished-garment and Opticut examples are product-discovery context only. No proprietary photographs, screenshots, CAD data or manufacturing information were downloaded, reconstructed, committed or redistributed. Their visual appearance is not a source for the new authored geometry.

## Supported construction and point-of-measure definitions

The original CC0 `Studio/src/patterns/template.json` defines `tshirt-5-piece-v1`, generator `1.0.0`, template ID `8f014f10-1f76-4af7-a327-b2316f9c2f1a`. Its SHA-256 is `4b323199f17e513bec2015b73ed4086f5a033b5255facf09717fa9bdf7930203`. This is source-template licensing, not a transfer of rights in a designer's project.

All coordinates/specifications are meters. Full front/back panels have hem Y=0 and high shoulder Y=body length. Front chest is at 0.68 × body length; front and back have the same side and shoulder seam lengths. Shoulder slope is zero in this bounded block. Back neck depth is `min(front depth × 0.25, 0.03 m)`. These derived choices are visible construction assumptions, not additional independent measurements.

| POM ID | Definition / actual generated endpoints | Supported range |
| --- | --- | --- |
| `bodyLength` | Vertical projection from front high shoulder at neck to the hem directly below it | 45–100 cm |
| `chestWidth` | Full front-panel horizontal width at the declared chest line; not body circumference | 36–80 cm |
| `hemWidth` | Full front hem horizontal width | 34–80 cm |
| `shoulderWidth` | Horizontal span between outer shoulder seam endpoints | 28–62 cm |
| `sleeveLength` | Straight centerline from sleeve cap apex to the midpoint of the developed hem | 8–42 cm |
| `sleeveOpening` | Half of the complete two-segment developed sleeve hem path | 10–35 cm |
| `neckWidth` | Full horizontal span between high-shoulder neckline endpoints | 12–28 cm |
| `neckDepth` | Front vertical drop from high-shoulder level to neckline center | 3.5–15 cm |

Each specification stores stable POM IDs, definitions/version, revision and size bindings, canonical values, optional tolerances, and authored/designer/graded source flags. Centimeter/inch changes affect presentation, not stored values. Tolerances are optional nonnegative design information, not certified factory capability.

Joint constraints reject hem width more than 5 mm above chest width, shoulder ≥ chest, neck width ≥ shoulder, neck depth ≥ 45% body length, sleeve opening ≥ 70% chest width, or sleeve length below 35% opening. A bounded bisection solves each cubic sleeve-cap half to 1.03 × its corresponding armhole length; incompatible caps are rejected. The two independent sleeves both have front/back cap and underarm correspondence. Neckband lower and folded-upper attachment segments are each 90% of the matching front/back neckline; end joins match. The 3% cap ease and 10% neckband reduction require designer/material review; neither is measured fabric stretch.

Pieces carry stable point/line/cubic/edge IDs, main/rib assignments, cut quantity, handedness, grain direction, fold information and normalized-arclength paired notches (single front / double back). Seam orientation explicitly says whether ordered edge lists align or oppose. The neckband fold is an identified internal line, not a cutting boundary. Full panels are not on-fold half patterns.

Finished seam boundaries are distinct from the cutting boundary. Supported allowance is a 10 mm outward miter offset of adaptively sampled curves, with ≤0.5 mm curve approximation and a 4× miter limit. Excessive corners, nonfinite/degenerate boundaries, self-intersections, bad seam correspondence and unsupported constructions fail rather than being clamped into a successful pattern. Generic allowances at hems do not specify a production hem finish. Endpoint tolerance is 1 μm; declared seam-length tolerance is 0.5 mm. Numerical consistency does not authorize cutting approval.

## Modules, preview mapping and model independence

- `patterns/generator.ts`: authoritative deterministic piece generation, curve/offset/assembly validation, measured endpoints and generated front/back technical flats. UI state is not the source of geometric truth.
- `patterns/preview.ts`: maintained `parametric-preview-v1` adapter consuming the admitted pattern. Refined torso surfaces use a garment-only authored depth profile; sleeve tubes preserve top length and developed opening perimeter; a folded-width collar follows the neckline. Curvature, cap pose and collar mapping are non-isometric. It is not a cloth solver.
- `domain/development.ts`: specification/size identity, independent grading, rebase, revision rebinding and canonical regeneration validation.
- `DevelopmentEditor.tsx` / `PatternDrawing.tsx`: exact-unit numeric editing, POM diagrams and two direct handles, actual SVG pieces, size chart, comparison/history, inspection layers and vector navigation. All-pieces arrangement is an inspection grid, not nesting.
- The existing `repository` and `packages` implementations are retained unchanged. `projects`, `validation`, `GarmentViewer` and its rendering adapter are extended rather than replaced. The viewer retains context/error handling, controls, camera presets and explicit disposal.

Canonical 3D geometry remains right-handed, Y-up, meters, front +Z. The new garment local origin is high-shoulder Y=0. The original catalog's source-to-canonical transforms/hashes remain authoritative for models. Garment placement is a rigid translation to reference shoulder height (`model height × 1.5 / 1.8`, Z=0.055 m); switching models changes no garment vertex, normal, index, specification or size identity. No uniform mesh scaling or body replacement occurs during a POM edit.

Three-dimensional torso POMs use their declared horizontal/vertical projections. Sleeve length uses actual indexed surface endpoints; opening uses half the actual closed indexed hem path, not an unrelated marker or Euclidean shortcut. Polygonal radius correction preserves that path length. Admission checks finite/bounded geometry, unit normals, nondegenerate indexed triangles, consistent winding, source identities and all eight surface-bound measurements. Some valid 2D patterns cannot form the supported illustrative sleeve pose; the preview reports this explicitly and retains the valid specifications. Body intersection and material deformation remain unverified.

Comparison uses a single camera/model and a wireframe secondary garment, not independently auto-fitted viewports. Size/revision changes do not refit the camera. Pattern overlays share meter scale and high-shoulder datums; only explicit Fit drawing changes framing. Numerical tables compare each POM and compatible size-chart IDs. Legacy comparisons clearly lack historical POMs.

## Sizes, revision history and compatibility

Size labels are brand-defined. Up to eight sizes use a star of explicit per-POM deltas from the selected base. Editing a base measurement changes only that measurement across graded sizes; a zero length delta remains zero when chest width changes. Editing a nonbase measurement updates only its corresponding delta. Rebase preserves every absolute size value. Every size is regenerated/validated; an invalid size rejects the edit with its label.

Saving a design/material/name/specification/grade change appends an immutable garment revision. Project name, model, selected size, units and preview/comparison preferences are project metadata, not needless garment revisions. Restore copies an earlier design into a new revision with current lineage and a restoration source; no historical record is overwritten. An unsaved-current comparison target follows the newly appended revision, including newly added sizes.

Restoration keeps the selected size only if that stable size identity exists in the restored chart; otherwise it selects that chart's declared base. It clears stale comparison metadata without changing the fitting model or old revisions. Legacy comparison has one draft selection owner; V1 comparisons are transient, while V2 preview settings persist. Restored legacy designs can explicitly upgrade again rather than hitting a project-version no-op.

V1 project/package imports retain original authored outlines, assets and revisions with no invented POMs. Explicit upgrade appends a V2 parametric revision from labelled authored defaults. Restoring a legacy design inside V2 retains its legacy meaning and can later be upgraded again. Original revision IDs/content and static asset hashes/licenses remain unchanged.

## Contracts, persistence and exports

`Shared/Contracts/` retains V1 definitions and adds consumed V2 project/revision/package variants plus `GarmentSpecification`, `PatternDefinition`, `SizeSet`, `GradeRule` and development-state contracts. Canonical examples are exercised by domain tests. Imports, persistence and rendering enforce schema shape, versions, references, units, licensing/source identity, finite supported parameters, independent grade arithmetic and regenerated canonical pattern geometry. Stored validation reports are checked, not silently repaired.

The existing IndexedDB version/stores and optimistic save token remain. Atomic validation/save acknowledges only transaction completion; failed/invalid/conflicting writes preserve the last acknowledged project. Full editable history, size values/rules, selected preview state and permitted original assets survive reopen/import. Derived meshes are safely regenerated, not duplicated for every size/edit.

Generator/topology/preview versions are compatibility commitments. Future changes must retain the admitted old implementation or provide an explicit new-version upgrade; changing `1.0.0` outputs in place would invalidate reproducibility. This goal does not implement arbitrary generator plugins or imported executable geometry.

Limits remain 12 MiB package / 3 MiB mesh / 100 garment revisions, plus eight sizes. The byte ceiling can be reached before count ceilings. There is no unbounded history/mesh loading or arbitrary imported executable/URL resource. Source URLs are inert provenance. Browser-local storage is not a backup or encrypted vault; keep exported files separately.

Exports save the valid draft first:

- **CSV:** every size/POM with garment/revision/size IDs, endpoint and method definitions, units, value, optional tolerance, status and provenance. Text cells are formula-injection escaped.
- **Structured JSON:** revision metadata, source, complete size set/rules, specifications, versioned actual patterns and validation status.
- **SVG:** actual line/cubic seam boundaries, distinct sampled cutting boundaries, grain/fold/notch and seam metadata, piece labels/materials/quantities. Width/height and viewBox share millimeter values at 1:1 numeric scale, independent of viewport zoom. Print/import applications may still apply their own scaling; verify a known measurement before use.
- **On You `.onyou.json`:** bounded self-contained supported editable project/history and permitted catalog assets; import always forks to a new project identity and never overwrites unrelated work.

No DXF/AAMA/ASTM, complete tech pack, production CAD interoperability, factory-ready cutting, material calibration or sampling reduction is claimed.

## Verification receipt

Executed after the final production-code edit, using Node 22.21.1, npm 10.9.4, pinned dependencies and real Chromium/WebGL:

| Command / check | Actual result |
| --- | --- |
| `npm ci --ignore-scripts --no-fund --no-audit` | Installed 47 pinned packages |
| `npm run typecheck` | Passed, no TypeScript diagnostics |
| `npm run build` | Passed; static production bundle generated |
| `npm test` | 30 passed, 0 failed, 0 skipped |
| `env -u CI npm run test:browser -- --workers=2` | 10 passed, including the six retained foundation journeys; 0 skipped |

The browser check reused the owned production preview on port 4175. `CI` was unset for that command because the inherited CI flag otherwise refuses to reuse a running server; the first attempted browser launch correctly reported the occupied port rather than testing a different app. Normal CI can start its own configured preview. The build retains a nonblocking >500 kB chunk warning (approximately 1,023 kB JavaScript / 285 kB gzip); the warning was not suppressed.

### Numerical evidence

- Every POM changed independently in generated 2D endpoints (1% changes), with all eight measured values checked within 1 μm and unrelated independent values retained.
- Every POM changed actual 3D vertices (2% changes), with all eight indexed endpoint/projection/developed-path measurements checked within 1 μm. Measurement-only orphan vertices, bad indices, degenerate faces and inconsistent winding are rejected.
- Both sleeves' cap correspondences, side/shoulder joins and folded neckband constraints passed independent 2,048-segment curve-length sampling within the declared 0.5 mm seam tolerance.
- The rectangular neckband's actual cutting coordinates are 10 mm outside its seam boundary, not the erroneous 5 mm offset found during review.
- A 40 mm body-length change changes actual garment bounds by 40 mm within 0.01 mm, while admitted fitting-model buffers remain unchanged.
- The same size produces identical local garment positions, normals and indices on Fit Models A and B; only rigid placement changes.
- Centimeter/inch conversion round-trips within `1e-12 m`. Independent grading/rebase preserves actual absolute size values; zero length grading is not replaced by chest scaling.
- Actual exported SVG M/L/C coordinates, converted from millimeters, reproduce all eight POMs within 1 μm. Width/height and viewBox use matching millimeter values; this is not a test of echoed labels.
- Canonical examples, V1 upgrade/re-upgrade, immutable restoration, selected-size fallback, comparison identity, import tampering, atomic failure recovery and optimistic conflicts passed domain/repository checks.

### Actual browser workflows and inspection

The complete development journey creates a project, edits body length to 74 cm, observes changed SVG paths and rendered canvas pixels without replacing the canvas, adds `Roomy`, grades chest by +2 cm while length stays zero, compares sizes, changes fitting model with Side view retained, saves, compares an earlier revision, restores as a new revision, closes/reopens, exports/reimports exact supported history/assets, and downloads specifications.

Other journeys cover explicit V1 upgrade and legacy/parametric restoration, invalid dimensions/grades with last-acknowledged recovery, structured JSON and real SVG downloads, retained foundation navigation, invalid imports, failed browser writes and unsupported WebGL. Successful persistence/rendering is not mocked; only fault paths are injected.

Manual inspection used the actual application at 1365 px and 1024 px. Keyboard editing moved body length from 74 to 74.1 cm. A real 12 px pointer drag produced 76.878316 cm versus the screen-transform expectation of 76.878325 cm. No page controls/state were inserted to fabricate success.

Final resize inspection found and fixed an intrinsic-canvas/grid sizing feedback path. The renderer now observes/measures its fixed viewport, not the canvas's changing intrinsic dimensions. The canvas matches its 745 × 340 px surface at 1024 px; the complete selected model is visible, no horizontal page overflow occurs, and resize preserves Side view. The automated essential journey also checks both narrow and original desktop sizes. Fold text overlapping the narrow neckband was removed; its actual fold line and inspection text remain.

During implementation, focused checks exposed overescaped name/test regular expressions, missing revision-change bookkeeping, noncanonical negative zero in mirrored points, sleeve winding, restoration metadata/selection and canvas sizing defects. These were corrected before the final 30-test/10-journey run. No executed check remains failing.

Screenshots are actual browser captures. The development journey writes `graded-comparison.png` under ignored `Studio/test-results/`; rerunning the browser command reproduces it. Screenshots and downloaded synthetic review projects are not committed as product assets.

## Outstanding validation and product limits

- No designer has approved this construction, shoulder model, POM convention, notch registration, ease, neckband material behavior or hem finish. Designer/toile review is explicitly still required.
- The illustrative surfaces can intersect the body/base shorts; this was visible in side-view inspection. No collision/contact/drape solution or physical-fit guarantee is implemented. Increasing a mannequin's dimensions does not secretly enlarge the garment.
- Some valid 2D constructions exceed the supported illustrative sleeve pose and report a preview error. Their valid specifications remain available; no unsupported chart size is silently omitted.
- Automated browser execution was Chromium only. Safari/Firefox behavior, print-driver scaling, CAD/factory interoperability, material mechanics, physical grading and sample outcomes remain unverified.
- No physical iPhone, scanner test campaign, personal scan, garment sample or proprietary manufacturing reference was required or used. This receipt is independent of historical Goal 1/2 test counts.

## Future manufacturing / marker-making milestone

The piece sheet in this goal is an inspection/export presentation, **not a fabric marker**. No fabric nesting, consumption optimization, marker efficiency or mixed-size production planning is implemented or claimed.

A later module needs these explicit, revisioned inputs and outputs:

| Requirement | Preserved now / additional input needed later |
| --- | --- |
| Fabric width and usable area | Add declared roll width, selvedges, defects, usable polygon and length limits, all in meters; do not infer from an image |
| Material groups | Piece `materialGroup` separates main and rib; later bind each to an approved material/lot revision |
| Cut quantities | Piece identities, cut quantities and handed/mirrored construction are retained; later combine them with order quantities |
| Mixed-size ratios | Stable size IDs and actual per-size pieces exist; later add a revisioned order with quantity per size, not a universal S/M/L chart |
| Grain constraints | Actual piece grainline vectors are retained; later specify permitted grain tolerance and directional/nap constraints |
| Rotation and mirroring | Current mirroring describes authored piece construction, not permission to flip a nesting placement; future material/order policy must explicitly permit rotations and reflection |
| Piece spacing | Consume the actual cutting boundary and allowance, then require an additional machine/material spacing rule; never double-count allowances |
| Non-overlap | Validate every placement, containment, quantity and grain constraint independently of an optimizer's success code |
| Fabric consumption | Compute from actual legal placements and declared usable roll geometry; no estimate or efficiency percentage is imported from Ben's screenshots |
| Marker efficiency | Define numerator/denominator and handling of holes/selvedges/defects before reporting area utilization; a good percentage is not an optimality proof |
| Revisions and reproducibility | Bind immutable pattern, size, order, fabric/material and placement/optimizer versions; preserve source designs and export losses |

This later work should consume the current piece/edge/grain/material/quantity identities, not reinterpret the technical garment illustration as a marker. It requires manufacturer/designer discovery and interoperability tests before factory-readiness claims.

## Independent development tracks and next prerequisites

### Goal 4 — statistical avatar completion

Still separate from Studio garment development. Obtain written, commercially appropriate rights for model/code/weights/data/outputs before installing a statistical human model. Use purpose-authorized calibrated observation fixtures, explicit observed/inferred/unknown regions, held-out evaluation and uncertainty/abstention. Do not collect customer scans, retain scanner evidence secretly, upload personal body data or promote inferred output into current capture acceptance. The CC0 authored mannequin is a safe baseline, not a statistical completion model.

### Goal 5 — garment simulation feasibility

The next direct garment-development dependency is a bounded solver/vendor feasibility task using one supported T-shirt, explicit seams, one permitted standard model, one pose and versioned material assumptions. First obtain licensed runnable apparel-host/API access or an explicitly bounded permissive component evaluation; public vendor documentation is not a redistribution/headless grant. IPC/contact components alone are not a full garment solver.

Verify pattern/seam/unit interchange, run provenance, failure/unsupported states and a separate result adapter before product integration. Calibrated fabric thickness, areal density, warp/weft/bias response, shear/bending, damping/friction, contact behavior and physical sample comparison remain unavailable evidence gates. Do not infer them from a shader color or neckband construction ratio. Numerical simulation success does not authorize pressure, fit, exact sizing or sample-elimination claims.

Goal 6 brand-to-consumer publishing must use approved revisioned garment contracts, not fake scan records. Goal 7 accounts/collaboration/payments/production hosting remain outside this local authoring milestone.
