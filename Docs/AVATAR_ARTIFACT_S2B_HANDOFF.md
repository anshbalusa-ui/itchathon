# Segment S2B — Secure Local Geometry Artifact Storage

## 1. Starting state, branch and scope

Started from clean local `feature/avatar-geometry-s2a`, matching remote and open draft [PR #18](https://github.com/anshbalusa-ui/itchathon/pull/18), tip `a48e3d91331f6a306e97283358fcd5e999f2bf2c`. No newer S2A tip, uncommitted work, interrupted Git operation or existing S2B branch/PR was found. Created `feature/avatar-artifact-storage-s2b` from that tip. Its draft PR targets `feature/avatar-geometry-s2a`, not main or I1. No merge, force-push, duplicate #11 integration, scanner replacement or subsequent segment is part of this work.

Reviewed the S2A, I1, S0, S1A, unexecuted S1B checklist, data architecture and R0/R3 handoffs against the actual geometry contracts/kernel, renderer/session/adapter, lab model/view, profile schema/repository/resolver, tests, project and verification runner. S2A's private `GeometryResult` and fixture authorization are unchanged. I1 unlink/exclusive staging repairs, legacy preference ownership, scanner rejection, six R3 associations and original renderer remain intact.

**Implemented scope:** versioned synthetic-only artifacts containing actual generated mesh data; bounded decode/integrity/admission; protected namespaced disk operations; real file-derived Metal rendering; Save/Load/Delete/error/retry UI and lifecycle ordering. No real-person geometry or raw sensor evidence is persisted. No cloud, account, backend, payment, telemetry, external model/asset or paid service was added.

## 2. Artifact data and versioned format

The committed file is `reviewed-synthetic.geometry-artifact`. Format 1 is a sorted-key JSON envelope with a base64 binary mesh payload. JSON was retained for inspectable compatibility metadata; fixed-width binary mesh scalars avoid JSON Float-array expansion, padding ambiguity and count-driven allocations during mesh parsing. `SyntheticArtifactCodec` is Foundation/CryptoKit-only and can run independently of SwiftUI, ARKit and Metal.

The envelope stores:

- Format name/version and artifact revision 1; opaque lowercase UUID artifact ID.
- Reviewed fixture ID and fixture revision; only `surfaceA`/`surfaceB` are admissible.
- Algorithm `open-elliptical-loft-v1`, algorithm revision and mesh schema.
- Explicit right-handed +Y-up/+Z-forward floor-centred convention, metre units via `metresPerUnit`, scale exactly 1.
- Reviewed-synthetic provenance, synthetic geometry role, neutral illustration capability and numerical validation status.
- Observed synthetic section heights, interpolation policy, unknown-region policy and unsupported-region list.
- Vertex/index counts, min/max bounds, actual positions/normals/triangle indices and SHA-256 integrity information.

Binary payload layout, little endian:

1. UInt32 vertex count and UInt32 index count.
2. Six Float32 values per vertex: position xyz, normal xyz.
3. UInt16 triangle indices.
4. Six Float32 bounds: minimum xyz, maximum xyz.

There is no native SIMD padding in this format. Each reviewed A/B artifact has 144 vertices and 720 indices; binary payload is **4,928 bytes**. A standalone run observed a **7,629-byte** B envelope. That file size is an observed example, not a required incidental encoder-output length.

SHA-256 covers the complete binary mesh payload, including its counts and bounds. Metadata is separately restricted to known values and compared with the approved fixture output. The digest detects corruption; it is **not authentication or source authority**. An opaque UUID identifies a write, not a person/account or an authorization grant. Every new successful save has a new artifact ID; the same mesh retains the same content digest. Revision/algorithm compatibility, not a registry of old UUIDs, controls stale-format rejection.

No imagery, depth maps, person masks, account identifiers, measurements or confidence percentages are fields in the contract. The encoder cannot accept arbitrary imported geometry or serialize unknown source fields.

## 3. Bounded codec and validation policy

| Bound | Enforced limit |
| --- | --- |
| Raw file before JSON decode | 262,144 bytes |
| Decoded binary payload | 131,072 bytes |
| Vertex / index count | 2,048 / 12,288, reusing `GeometryMesh` caps |
| Index representation | UInt16, range-checked against actual vertex count |
| Requested payload size | Checked count multiplication/addition before mesh-array reserve/allocation |
| Concurrent lab storage jobs | One physical job; one coalesced accepted delete/reload intent |

The repository checks regular-file size before reserving read data, reads in capped chunks and detects growth beyond the cap. The codec checks raw size before parsing, reads a minimal version header before decoding the full envelope, checks decoded payload size/count bounds and checked exact byte size before constructing mesh arrays. Malformed/truncated/trailing/count-mismatched input rejects. Codable/JSON/base64 have bounded overhead under the raw-file cap; an aggregate peak heap figure is **not measured or claimed**.

Decoded Float values must be finite. Existing geometry validation checks index range, outward normalized normals, winding agreement, nondegeneracy, bounds consistency and the admitted world envelope. Envelope and binary bounds/counts must agree. Metadata, source, roles, capability, observed/interpolated/unsupported regions and all revisions must match the supported contract. Invalid mesh failures are converted to typed artifact corruption, not exposed as raw parser or private-path errors.

Unknown format/artifact revision returns `unsupportedVersion` before full payload decode, including future envelopes with a changed shape. Unknown fixture/provenance returns `unauthorizedSource`. Incompatible role/capability or noncanonical mesh returns `incompatibleArtifact`; corrupt syntax/digest/size/topology gets the appropriate typed category. Nothing silently migrates, regenerates over or deletes incompatible data.

## 4. Separate disk admission — no private authority weakening

`GeometryResult` remains file-sealed in the original geometry domain. Neither Codable DTOs nor disk strings can call its initializer or mint its `GeometryAuthorization`. No `reviewed: Bool` or `.savedAvatar` promotion was introduced.

`SyntheticArtifactCodec.decode` first validates the decoded mesh and semantic metadata. It then independently regenerates the currently approved deterministic A/B fixture **only for verification** and compares every decoded position, normal, index, bounds and relevant metadata with that expected result. Comparison is exact Float/value equality for the current runtime. A changed math implementation that no longer produces identical approved output fails closed as incompatible; future compatibility needs an explicit revision policy, not an undocumented tolerance or migration.

Only this successful path can create `VerifiedSyntheticArtifact`. Its initializer is file-private, its mesh/identity immutable and it is not Codable. Crucially, the token retains the **decoded arrays**; it does not substitute regenerated arrays. Its consumption-time `validate()` rechecks the immutable token/mesh without repeating canonical reconstruction on the main actor. Canonical generation runs in the codec/repository actor off the UI actor.

Forging provenance, recomputing a digest or swapping fixture metadata cannot authorize arbitrary/person-derived geometry. Even matching all descriptive strings leaves an altered mesh unequal to the approved fixture. Scanner/unknown provenance and all personal roles reject. This is a source-code trust boundary for the internal synthetic lab, not cryptographic proof against malicious application modifications.

## 5. Repository namespace and ownership

Default storage is Application Support / `FitCheckSyntheticGeometryS2B` / `reviewed-synthetic.geometry-artifact`, entirely separate from `fitcheck-avatar-profile.json`, legacy defaults, catalog assets and garment files. The actor and URL are initialized lazily when the Debug lab model is constructed; no artifact I/O occurs until a storage action. There is no startup auto-load or implicit profile creation.

`SyntheticArtifactRepository.shared` is the default app coordinator. Independent instances open the same verified directory and lock the persistent `.repository.lock` inode with `flock(LOCK_EX | LOCK_NB)`. Conflicting cooperating readers/writers/deleters receive typed `conflict`; none waits indefinitely while holding an actor. No suspension occurs inside the locked filesystem transaction. Each operation opens/closes its own descriptors, and each save gets a unique exclusively created `.pending-<UUID>.stage` file. A writer cannot remove or reuse another actor's shared pending slot because no such slot exists.

The directory is mode 0700; staged/committed files and lock are mode 0600. Actual standalone metadata confirmed these modes. Namespace ownership assumes an OS-selected private app-container parent, or an explicitly assigned isolated native-test directory—not an arbitrary user import path. Missing parents are created only in that assigned scope. Namespace lstat/fstat device/inode/owner checks pin the intended directory; a replaced/symlinked namespace fails closed. Leaf operations use `openat`, `fstatat`, `renameat` and `unlinkat` relative to its open descriptor, with no-follow/nonblocking regular-file and single-hardlink checks. FIFOs, directories, symlinks and multiply linked leaves are not read as artifacts.

## 6. Protection and backup policy

The entire dedicated directory is excluded from backup on every open, including when it contains invalid records, an unswept crash stage or the coordination lock. On iOS, complete file protection is applied to the directory and files. Each staged inode receives protection before payload writing and backup exclusion before publication; valid loaded records are also brought under the same protection/backup policy. Metadata failures propagate rather than being suppressed.

Foundation protection/backup setters are pathname APIs, bracketed by identity checks. The simulator accepts the protection setter but exposes **no protection-class key**; actual native evidence records this limitation. Simulator assertions verify backup exclusion and 0700/0600 modes, not class A or a keybag. On physical iOS, the repository reads the applied class back and fails closed before payload publication unless it is complete protection; a device-only native assertion requires the same. That branch is compiled by the generic-iPhone app build, but physical class/locked-device validation remains **NOT RUN**. No missing simulator value is represented as successful physical protection.

## 7. Save, commit and failure semantics

Save validates the original sealed generated result and serializes a bounded payload with identity in one pass; it does not decode/regenerate its own output just to retrieve the identity. Under the shared lock:

1. Validate an existing committed file, if any. Corrupt/unsupported bytes remain untouched; replacement is rejected until explicit deletion.
2. Exclusively create a unique owned staging inode (`O_EXCL | O_NOFOLLOW`), retain its descriptor and record identity.
3. Apply protection, write bounded bytes, check cancellation, fsync, apply backup exclusion, and verify staging name/descriptor/size.
4. Recheck pinned directory, expected destination identity and current committed validity after the boundary checkpoint.
5. `renameat` atomically replaces the known valid committed record; fsync the directory before confirming saved status.

Any failure **before rename** leaves the prior committed artifact intact. Cleanup may unlink only the exact staging inode that this operation created; a replaced regular file, symlink or directory is preserved. There is no recursive removal and no orphan sweep based merely on a filename suffix. Crashed stages are ignored on load and left intact because a new owner cannot prove creation ownership from their names alone. Ordinary operations retain no extra stage; repeated crashes can leave inert small stages requiring separately authorized app-data cleanup. This is intentionally safer than deleting an unproven file.

Rename/unlink is the visibility commit point. If a later directory fsync or acknowledgement checkpoint fails, the operation returns **`durabilityUncertain`**, not a false ordinary pre-commit failure or confirmed saved/deleted status. The new valid record or deletion may already be visible; an explicit Load determines current state. No unsafe rollback overwrites another entry. Power-loss durability and physical storage behavior are not claimed from simulator tests.

Cancellation is checked before operations, between bounded read/write chunks, after partial-write checkpoints and immediately before mutation. It is cooperative: cancellation after the commit point cannot undo a real mutation. The UI separately rejects late acknowledgements.

## 8. Load, delete and interrupted-file recovery

Load opens only the committed reserved filename, never stages. Missing directory/file returns nil. A no-follow/nonblocking descriptor prevents special-file hangs and alias reads; initial size and every appended chunk are bounded. Integrity, semantic/mesh validation and synthetic admission all complete before a verified token is returned. Corrupt, oversized or unsupported files remain intact for explicit user action.

Delete is explicit, nonrecursive and serialized by the same lock. It opens and holds the committed inode until unlink, avoiding an unlink/recreate inode-reuse (ABA) match. Fresh kind/device/inode/link/size checks after the injected boundary reject unexpected substitutions. An ordinary corrupt/unsupported regular record at the reserved application-owned filename can be explicitly deleted; symlinks, directories, hardlinks and substituted foreign regular entries are preserved. Missing deletion is idempotent. Stages belonging to other/unknown operations are never swept.

The lock coordinates **cooperating repository instances**, not arbitrary filesystem writers. Identity checks and Foundation metadata calls still have check/use windows; no portable compare-inode-and-rename/unlink primitive is claimed. A writer that ignores the lock and mutates the private directory after the final check is outside this threat boundary. This is not a hostile-filesystem transaction, account-isolation solution or arbitrary multi-process database. Tests force the documented kind/inode/root substitutions at the actual boundary seams and verify preservation; they do not turn those seams into a universal race-proof claim.

## 9. Existing Metal renderer consumes decoded data

`GeometryRendererAdapter.mesh(from: VerifiedSyntheticArtifact)` validates the admitted token, maps its decoded positions/normals into existing renderer vertices and shares the decoded immutable index array. `RendererSceneSession(artifact:)` passes that CPU mesh to the existing generated-base-mesh initializer. No `GeometryResult` is minted and no default mannequin is substituted. Existing buffers, shaders, camera, depth, orbit/reset and disposal are reused.

The loaded scene keeps the synthetic role and cannot install a garment or alter the six exact R3 associations. Native tests compare **every actual Metal buffer vertex/normal/index** against the loaded token and saved fixture, distinguish it from an independently generated A scene, and verify buffer release on delete. A/B retain the same material; visible differences come from geometry. GPU data is never serialized as opaque Metal buffers or personal artifacts.

## 10. Lab UI and source truth

Debug integrated hub → Avatar Geometry Lab exposes **Save generated synthetic artifact**, **Load saved synthetic artifact**, **Delete saved synthetic artifact** and the real operation status. Generated and loaded scenes have distinct visible/accessibility source labels. The lab states:

> Synthetic geometry only. Not a personal scan or verified avatar.

Saving requires a current valid generated result and waits for real disk publication/acknowledgement. Loaded geometry is not relabelled as a generated result; regenerating a fixture is required to save a new result. Load clears previous CPU/GPU geometry immediately and reports loading, loaded, missing, corrupt, unsupported, incompatible, blocked-path, conflict or I/O failure from the real operation. Missing/failure shows no stale surface. Explicit delete clears the loaded scene, and later load reports missing. No error path claims a personal saved avatar or creates placeholder geometry.

Controls are scrollable under the pinned native scene/failure region, support accessibility text/identifiers and do not ask for camera permission. Rotate/reset apply to actual disk-derived geometry. Unknown/incompatible bytes are not fixed by a fake UI flag; the user can explicitly delete and regenerate/save a reviewed fixture.

## 11. Async ordering and lifecycle

The original bounded CPU generator retains its single-flight/coalesced fixture behavior. A separate single physical storage slot serializes save/load/delete; Generate and storage actors can each have one bounded job, never an unbounded save queue.

Save captures an immutable generated snapshot. Fixture changes cancel/invalidate the save acknowledgement; even a cancellation-ignoring repository cannot later report old A as saved B. Duplicate rapid save/load commands are disabled/rejected until the active storage job acknowledges. Load has a storage epoch plus the display generation; replies after selection change, background, dismissal or fresh entry cannot create a scene. Actor work does not retain the model across awaits.

Delete requested during a load/save cancels it and is queued behind its **physical** completion. A subsequent fixture selection cannot drop that accepted deletion. No delete/read overlap can resurrect an old loaded scene. The optional task handle is returned for an immediately started operation; a queued delete has no immediate handle, and UI completion comes from actual status.

Background releases loaded/generated CPU/GPU state and cancels pending acknowledgement. Foreground reloads only a still-current saved-artifact intent, waiting for an old physical job to exit if needed; it does not pretend regeneration is a disk load. Explicit fixture generation supersedes that intent. Close resets selection/source/intent; a fresh entry starts a generated fixture, and only an explicit Load reads disk. Weak callbacks plus scene identity prevent an old render failure from invalidating a replacement scene. Native cancellation-ignoring tests exercise these orderings and deallocation.

## 12. Controlled UI fixtures and Release boundary

The only test namespace argument accepts a canonical UUID and selects a child of app-private `FitCheckSyntheticGeometryS2B-UITests`. It cannot supply an arbitrary path, mesh, profile or payload. A second Debug-only argument can create only fixed nonpersonal `corrupt` or `future` bytes in that isolated UUID directory on first Load, using exclusive creation. It still calls the real repository for every action; it is not an in-memory saved Boolean or fake load. Fresh UUIDs and explicit deletion keep tests independent. Normal default state is not cleared for tests.

All codec, repository, test setup, UI controls and artifact renderer overloads are `#if DEBUG`, with no packaged artifacts. Normal Release cannot recognize these arguments or construct artifact storage. The verification runner preserves all prior gates and adds S2B binary positive/negative controls, a real Release UI selector and an all-four-bundle prohibition on runtime artifacts, stages, lockfiles or synthetic storage namespaces being packaged as resources. No profile/default store was repurposed or migrated.

## 13. Verification provenance and current evidence

Standalone Swift execution of the actual contracts/kernel/codec/repository passed separate-process A save/load, B replacement/load, delete/missing reload, future-version rejection and explicit recovery. The final frozen source was recompiled and exercised through **14 independent process invocations** in a fresh isolated namespace. `final-cold-process-storage-smoke.json` records the source digest, stdout, matching IDs/digests, actual 0700/0600 modes, 144/720 counts and bounded serialized sizes. This is independent of XCTest and uses no renderer, camera or profile data.

The first focused Xcode attempt failed before tests because an awaited geometry expression appeared inside an XCTest autoclosure; it was evaluated before `XCTUnwrap`. The next compiled focused run recorded **49 passes / 1 failure**, and the following expanded run **51 passes / 1 failure**. Both failed solely on an invalid simulator protection-metadata assumption: casting then requiring a value could not work because this runtime exposes no protection-class key. The passing portions included the real filesystem/canonical/GPU/lifecycle checks and all six UI scenarios, including cold A/B, negative files and largest text.

The invalid metadata assertion was replaced by actual observable privacy requirements (backup exclusion and private file/directory modes), with complete-protection class assertions retained for physical iOS and fail-closed verification in device code. It is not a skipped functional regression or a simulator-nil value pinned as expected behavior. The corrected focused native run passed **46/46**, zero failures/skips; `supported-privacy-proof/20019561-4EDF-4291-9D18-CF6490B46EB1.txt` records that the runtime did not expose a protection key. Actual cold A/B and accessible disk-rendering screenshots were separately inspected. No physical protection claim is inferred.

Failed bundles `focused-storage.xcresult`, `focused-storage-compile-fix.xcresult` and `focused-storage-metadata-fix.xcresult`, plus passing `focused-storage-supported-privacy.xcresult`, remain under `/Users/anshbalusa/fitcheck-s2b-artifacts`. Failures are not passing evidence, and historical S2A totals are not substituted for fresh S2B verification.

### Final frozen-source execution

```sh
caffeinate -disu /usr/local/bin/python3 Scripts/verify_development.py \
  --output-root /Users/anshbalusa/fitcheck-s2b-artifacts/final-verification
```

The runner discovered the current available simulator rather than using a historical hardcoded device argument. It used the iPhone 17 simulator on iOS 26.5, Xcode 26.5 and XcodeGen 2.46.0. Its before/after build-input SHA-256 and independent post-run comparisons agree: `76c848066153a492e7230edb1b3ec8d03a7f74591d46a986e3e805f4bfff5867`. Only handoff/README and external evidence/cleanup changed afterward; they are outside the build-input digest.

| Fresh S2B gate | Actual result |
| --- | --- |
| XcodeGen and clean complete Debug build/unit/UI | **307/307**: 284 unit and 23 UI; zero failures/skips |
| Preserved regression coverage | All prior 267 Debug cases remain, including profile/recovery races, legacy persistence, scanner, catalog, R0–R3 and S2A |
| Focused corrected native run | **46/46**, zero failures/skips; includes all 37 new native artifact cases and 9 existing geometry/model/Metal cases |
| Unsigned generic-iPhone SDK build | Passed; device-only protection readback code compiled, physical execution not claimed |
| Normal Release simulator build | Passed, actual `ENABLE_TESTABILITY=NO` |
| Separate Release isolation suite | **14/14**: 8 unit and 6 UI; zero failures/skips; every requested selector executed, including artifact isolation |
| Actual Debug / normal Release Mach-O checks | All prior and S2B positive controls present in Debug and absent from normal Release |
| Actual bundled runtime-storage exclusion | All four apps contain no synthetic artifact, stage, lockfile or storage namespace resource |
| Reviewed garment resource hash | Source and both Debug SDK bundles retain `ecc2df7e57f5a12ac89f4bd16bb51d101718780ee609a72f41c8ff1b653f7f30`; both Release apps exclude development mesh/resources |
| All four actual privacy manifests | Exactly `35F9.1`, `CA92.1`, `C617.1`; tracking false, collected-data list empty |
| Final independent cold storage smoke | **14 separate processes** on frozen source: A/B save/load/replace, future rejection, explicit recovery, delete and cold missing reload |
| Final real native visual smoke | Inspected actual A/B disk-derived Metal surfaces, explicit unsupported failure without stale mesh, cold missing/deleted state and largest text |
| Direct normal Release + S2B flags | Actual non-testable app opens legacy home; neither default nor fresh test namespace existed before or after launch |
| Physical protection class / keybag / LiDAR | **NOT RUN**; simulator exposes no class key and is not physical protection evidence |

Final local evidence: `/Users/anshbalusa/fitcheck-s2b-artifacts/final-verification/verification-78s13w90`. It contains exact command/version logs, test summary/tree JSON, `DebugTests.xcresult`, `ReleaseTests.xcresult`, `verification.json` and the Debug simulator, iPhone SDK, normal Release and testable Release builds. These are **local artifacts, not uploaded GitHub artifacts**. S2A's historical 267/13 totals are not represented as fresh S2B results.

### Test behavior and visual observations

- `SyntheticArtifactCodecTests`: **13** cases, including A/B decoded-mesh equality; stable payload integrity with distinct write IDs; raw/payload caps; malformed/truncated input; forged algorithm/schema/revisions/coordinates/scale/provenance/role/capability/fixture/identity/counts; changed-shape future header; recomputed-digest nonfinite/normal/topology/bounds attacks; exact canonical mismatch and cancellation.
- `SyntheticArtifactRepositoryTests`: **17 simulator cases**, covering cold owner and replacement, partial/pre-commit failures and preserved prior bytes, explicit corrupt/future deletion/recovery, ignored orphan staging, stage/destination/root/symlink/directory/regular substitutions, nonrecursive delete and ABA pinning, hardlinks/FIFO/capped read, blocked parents, cross-instance read/write lock conflict, cancellation/clean retry, real private modes/backup exclusion and post-commit durability uncertainty. A separate physical-only protection-class assertion remains **NOT RUN**, not counted as a simulator pass.
- `SyntheticArtifactLabLifecycleTests`: **7** cases, including every actual Metal vertex/normal/index matching the disk-derived mesh, no `.savedAvatar` promotion, stale/cancelled Save A versus current B, duplicate-action exclusion, late load after selection/close, delete queued behind a cancellation-ignoring load, foreground-only current reload, invalid-file preservation/recovery and weak owner/CPU/GPU release.
- `AvatarGeometryUITests`: **3 new Debug scenarios** plus preserved S2A cases. The cold flow saves A, exits, terminates the app, loads A from disk and rotates/resets it; then saves/reloads B, changes back to A, cold-loads B with different pixels, deletes and cold-loads missing. Negative files use real bytes and require explicit delete before replacement. Largest Dynamic Type exercises real file-backed rendering and all storage controls. **1 new Release scenario** verifies flags/controls cannot expose persistence.

Final screenshot directories are `final-cold-a-b-proof`, `final-negative-file-proof` and `final-accessible-proof` under the evidence root. Actually inspected A `7C4CBF51-6C97-48A8-ABBF-447C29C2BA90.png`, B `1AE1845D-7E07-4AC6-93E9-80704516E15F.png`, unsupported file `942DD47B-E9DE-4348-9117-DA8C2A9754B1.png`, missing after cold deletion `E97CCC9D-ECEE-4A69-B014-A3ED78BA4DBD.png` and accessible loaded mesh `DB23E486-DB0F-4BCD-A7D7-721FF01C6D61.png`. Source labels and genuinely distinct same-material meshes are visible. These are not inferred from attachment names alone.

`final-visual-and-release-filesystem-proof.json` records those observations and the actual default/test namespace absence before/after a direct normal Release launch with S2B flags. `direct-final-normal-release.png` shows legacy home. `final-cold-process-storage-smoke.json` records the independently compiled consumer's actual operations and sizes. Throwaway smoke source/executable were removed after proof; evidence and failed result bundles remain. No raw personal geometry or scan data appears in them.

### New / changed files

| Files | Purpose |
| --- | --- |
| `Sources/Geometry/SyntheticArtifactCodec.swift` | Versioned bounded format, SHA-256 integrity and independent sealed disk admission |
| `Sources/Geometry/SyntheticArtifactRepository.swift` | Protected private namespace, coordinated descriptors, atomic publication and nonrecursive identity-aware deletion |
| `Sources/Geometry/SyntheticArtifactLabStorage.swift` | Lazy default coordinator and fixed UUID-scoped Debug UI negative-file setup |
| `Sources/Geometry/AvatarGeometryLabModel.swift`, `AvatarGeometryLabView.swift`, `GeometryViewport.swift` | Real storage states/actions, serialized async ordering, current disk-loaded ownership/source and accessible controls |
| `Sources/Rendering/GeometryRendererAdapter.swift`, `RendererSceneSession.swift` | Narrow verified decoded-mesh adapter/initializer; no geometry-domain authority change |
| `Tests/SyntheticArtifactCodecTests.swift`, `SyntheticArtifactRepositoryTests.swift`, `SyntheticArtifactLabLifecycleTests.swift` | Bounded adversarial decode, real filesystem/concurrency and actual-GPU/lifecycle regressions |
| `UITests/AvatarGeometryUITests.swift` | True cold-process A/B persistence/rendering, negative-file/recovery, accessibility and Release isolation |
| `Scripts/verify_development.py` | Preserve prior gates, add artifact markers/selector and packaged-runtime-file exclusion |
| `Docs/AVATAR_ARTIFACT_S2B_HANDOFF.md`, `README.md` | Actual format, authority, ownership, evidence, entry instructions and limits |


## 14. Privacy and future real-artifact review

Only approved first-party synthetic A/B meshes can be persisted or admitted. No scanner/capture coordinator connects to the store. No real RGB/depth/mask data, body measurements, identity or account values are saved/logged/uploaded. Typed error strings omit private paths and raw payloads. UI/digest evidence concerns nonpersonal authored fixtures only.

`AvatarProfileRecord`, `AvatarProfileRepository`, `.savedAvatar` readiness, legacy preferences and FitEngine remain unchanged. A synthetic artifact's existence or successful load cannot change `AvatarEntryResolver`. Existing boot-time `35F9.1`, UserDefaults `CA92.1` and file metadata `C617.1` declarations remain justified; descriptor stat/size/kind operations reinforce the existing file-metadata reason. No new required-reason category or collection/tracking declaration is introduced.

Future real-person artifacts need independent source admission and physical evidence approval, separately versioned provenance/uncertainty/compatibility, protected storage review, consent, account isolation, deletion/backup policy, migrations and stale-result semantics. Exact fixed-fixture comparison must not be removed merely to make a real scanner file load. S1B, calibrated RGB/depth/person association, physical repeatability, locked-device protection and performance remain **NOT RUN**. No future account policy or personal persistence is implicitly approved by this lab.

## 15. Operational limits and verdict boundary

One namespaced regenerable synthetic artifact is committed at a time. Only current fixed fixtures/revisions load; incompatible data requires explicit deletion, not migration. Unknown crash stages are retained rather than guessed-owned. File locks are cooperative and Foundation path metadata has a stated private-container trust boundary. Complete protection behavior while physically locked, power-loss durability, sustained RSS, FPS, thermal/power and actual LiDAR performance are not measured or claimed.

**GO for completed S2B internal synthetic-artifact storage and draft review:** real bounded codec/repository, independently admitted decoded meshes, cold-process persistence/rendering, failure/lifecycle behavior, preserved regressions and all fresh Release/privacy gates passed. **NO-GO for real/personal artifact persistence, verified personal avatars, calibrated reconstruction, garment fit or commercial release.** Physical protection class/keybag and LiDAR remain unexecuted; cooperative filesystem trust and durability uncertainty remain explicit. Nothing was merged, and no cloud/account/profile integration, S2C or other next segment was started.
