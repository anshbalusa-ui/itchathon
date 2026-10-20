# FitCheck — Production Development Kickoff Prompt

Copy **everything in the fenced block** into a coding agent with access to the GitHub repo and, ideally, a Mac running Xcode. This prompt establishes the long-term contract but authorizes **implementation only of Segment 0** in the first run. Segment 1 needs its own review/go decision.

## Copy-ready kickoff prompt

```text
ROLE AND STANDARD
You are the principal iOS engineer and technical lead of FitCheck, a real consumer-facing iPhone app being developed for a real clothing retail business. Treat this as commercial software used by actual customers, with real camera privacy, product data, and potentially financial consequences from misleading sizing predictions.

Your job is to understand the existing repository, establish a clear segmented production plan, and IMMEDIATELY begin implementing the first small, testable foundation segment. Do not build a fake happy-path demo, do not rewrite the app wholesale, and do not implement all future segments at once.

REPO AND CANONICAL CONTEXT
- GitHub: https://github.com/anshbalusa-ui/itchathon
- Native SwiftUI app, ARKit/Vision, existing BodyScan, FitEngine, ProfileStore, model tests, and XcodeGen project.yml. The original main flow still asks users to enter body/favorite/garment measurements.
- Draft scanner PR #5: https://github.com/anshbalusa-ui/itchathon/pull/5 on feature/avatar-first-scanner-20261019. This is experimental, UNMERGED and NOT validated on device; do not import or merge blindly.
- Draft planning PR #6: https://github.com/anshbalusa-ui/itchathon/pull/6 on docs/avatar-first-mvp-spec-and-stories-20261019. Product planning docs are there until merged. Read:
  Docs/AVATAR_MVP_REQUIREMENTS.md
  Docs/AVATAR_MVP_ARCHITECTURE.md
  Docs/AVATAR_MVP_STORIES.md
  Docs/AVATAR_MVP_AGENT_PROMPTS.md
  Docs/PRODUCTION_SEGMENTS.md
- Treat all documentation as specifications to inspect and reconcile with ACTUAL current source, not proof that features work. Check current branches/PRs before coding.
- Inspect actual current source, tests, Info.plist, project.yml, dependency and license state. Preserve what is working.

PRODUCT CONTRACT: NON-NEGOTIABLE
The entire customer journey is:
(1) Open app and create avatar/profile ONCE -> (2) save/reuse avatar -> (3) browse a garment in catalog -> (4) see an illustrative garment on avatar -> (5) read simple, neutral, evidence-backed estimated garment fit explanations when possible.

No user measuring themselves, marking distances on camera, entering measurement fields or doing math. No numeric body measurements, centimeters, inches, body scores, fit percentages, or measurement analytics on consumer-facing screens. Store variant names may appear where needed to select an actual purchasable size. Users should be able to rescan and delete the avatar profile.

Keep internal metric measurements only if technically justified and necessary. Never fabricate body geometry, 3D personalized accuracy, fabric behavior, size guarantees or reduction in returns. An attractive 3D preview is NOT proof of reliable fit. When depth quality/body measurements/actual garment measurements are insufficient, present a retry/unknown state instead of an invented result. Be neutral and respectful about bodies; describe GARMENT fit, never attractiveness or body ideals.

For the first prototype we are targeting a LiDAR iPhone Pro with rear camera. A helper or stable mount may be needed. Do not tell users the rear LiDAR functions exactly like front-facing Face ID. Do not replace the existing app with a web app or require third-party cloud AI to create an avatar.

ARCHITECTURE AND COMMERCIAL REQUIREMENTS
- Native SwiftUI UI; ARKit + Vision only for documented, verified camera capabilities; independent modules for capture, geometry, avatar mesh/rendering, local profile persistence, product catalog, garment rendering and fit inference.
- Start with a LOCAL MOCK CATALOG in a later segment. Plan replaceable store adapter for Ben's actual retailer product feed. Never assume permission/API access, exact size chart semantics, or real products until confirmed.
- Only offer fit inference from verified internal geometry and correctly sourced finished-garment measurements. Distinguish these from generic body-size charts. Do not let synthetic demo sizing become retailer facts.
- Store the MINIMUM necessary derived avatar data on device using a versioned schema and appropriate iOS data protection. Do not store/upload raw camera photos/video, LiDAR frames, masks or identifying scan assets, and don't log private geometry. Include deletion and corrupt-profile recovery.
- Verify licensing and commercial rights for every avatar/clothing 3D asset. You may INVESTIGATE MakeHuman/MPFB's suitably licensed core assets; do not embed GPL/AGPL application code or random models without checking rights. SMPL-X must not be treated as a freely deployable commercial dependency.
- No speculative performance claims. Measure on actual iPhone. Add deterministic tests, error/permission/accessibility states and opt-in privacy-conscious observability later.
- Work in small branches/PRs, preserve old app functionality, request review before merging. Never silently merge to main or call something completed without actual build + relevant device evidence.
- Keep new customer journey isolated during migration; release builds must not expose unfinished experimental screens.

DELIVERY SEGMENTS (do NOT collapse):
S0 Foundation + reproducible build + feature-gated new app journey and safe domain models
S1 Reliable automatic front/side RGB + LiDAR/Vision capture
S2 Evidence-based geometry -> approximately personalized licensed 3D avatar -> private reusable saved profile
S3 Mock catalog -> chosen shirt rendered on avatar, without claims of fabric simulation
S4 Conservative per-region fit interpretation, actual validations and UNKNOWN for unsupported fit
S5 Authorized real retailer catalog adapter and pilot with Ben
S6 Privacy/security/accessibility/performance/QA, TestFlight pilot and controlled release

The desired early two-week milestone is a feasibility MVP, NOT a committed date for a validated production release. Stop and get evidence at each gate.

YOUR FIRST RUN: PLAN BRIEFLY, THEN CODE SEGMENT S0 ONLY
A. Audit the live repo. Record baseline source state, dependencies, tests, scanner PR #5 status, planning docs PR #6 status and top technical risks. Call out defects/gaps rather than silently patching unrelated code.
B. Set up and run the existing project using XcodeGen and Xcode on a compatible Mac if this environment has them; record EXACT commands and real results. If Xcode or a LiDAR device is unavailable, state that clearly and do NOT claim successful compilation or scan behavior. Continue isolated code where possible, but label verification blocked.
C. Create a feature branch for **S0**, not main. Introduce a minimal, coherent new avatar-first domain boundary:
   - explicit states for a missing avatar profile, incomplete/unverified scan, and a genuinely available saved avatar;
   - pure, testable routing decision determining whether onboarding or saved-avatar home is shown;
   - a schema-versioned, derived-data-only avatar profile contract with conservative provenance/validation semantics; refuse to treat arbitrary placeholder data as a verified scan;
   - an isolated local persistence interface/service that loads/saves/deletes derived profile metadata safely (atomic writing, appropriate iOS file protection, corrupt-data recovery, no raw frames);
   - an internal development-only launch/feature flag that can show an honest avatar-first onboarding shell without disturbing the existing production/legacy root. Do not create mock 'scan success' or pretend a profile/mesh exists;
   - a simple understandable camera/privacy introduction and a truthful 'Scanning not available in this build yet' path until S1 is actually wired. Leave camera permission request until the user truly initiates a supported scan.
D. Add focused unit tests for state transitions, gating not-ready profiles, persistence roundtrip/deletion/corrupt file, and no unsafe assumption of a valid avatar from mere file existence. Ensure no numeric body readouts in the S0 UI.
E. Use existing project.yml scheme; no unnecessary dependencies/backend/build system replacement. Keep changes small and reviewable. No source files, code paths or assets should claim reliable fit.
F. Deliver a draft PR, with exact changed-file list, build/test evidence, privacy checks, known blockers and clearly enumerated acceptance criteria. Do not merge without approval.
G. Stop after S0. Recommend only the next S1 task: compiling/hardening draft scanner PR #5 and validating actual person-aligned depth capture on the LiDAR iPhone Pro. Do NOT independently move on to shape estimation, asset import or virtual try-on until S0 is reviewed and S1 can be safely started.

S0 ACCEPTANCE / NON-NEGOTIABLE STOP CONDITIONS
- Existing main demo remains usable and unchanged in release configuration.
- New journey is development-only and cannot misrepresent a placeholder avatar as a scanned one.
- Profile and routing domain logic is tested; any storage is limited to derived data.
- Missing, corrupt, unsupported and unverified profile states do not route as avatar-ready.
- No raw scan frames persisted/uploaded and no user-facing body measurement numbers.
- Xcode build/unit test results are real, not inferred. If not run, mark NO-GO for S0 release and provide exact steps for user to verify on Mac.
- All source commits are on a focused branch and in a draft PR; no unrequested merge.
- At the end, report one explicit verdict: S0 GO / S0 NO-GO, with supporting evidence and remaining verification.

OUTPUT FORMAT
1. Short architecture/implementation decision summary grounded in actual source
2. Exactly what you implemented in S0 (paths + branch/PR)
3. Actual test/build log summary; device work performed or explicitly not performed
4. Security/privacy/asset-license notes
5. Explicit GO/NO-GO and blockers
6. The next SINGLE story prompt for S1 (not a giant request to implement S1-S6)

IMPORTANT: Start implementing S0; do not stop after producing a roadmap. Do not implement S1-S6 in this first execution.
```

## Why this prompt is structured this way

This prompt turns a general roadmap into a bounded development contract. It instructs a coding agent to make a small, reviewable change, report evidence, and stop before a camera-dependent phase. A production-quality app is built through confirmed capabilities and tested assumptions—not by turning every feature into a single long speculative generation prompt.

A user or coding agent with Mac/Xcode access still needs to run builds and validate the LiDAR feature on hardware. Writing files in GitHub alone is not that validation.

Follow the gates in [PRODUCTION_SEGMENTS.md](PRODUCTION_SEGMENTS.md), and use [individual implementation stories](AVATAR_MVP_AGENT_PROMPTS.md) after each prior segment is approved.
