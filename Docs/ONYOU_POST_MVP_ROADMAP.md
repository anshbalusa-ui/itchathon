# On You — post-MVP scope and dependencies

## Product decision

The current MVP is **offline, local avatar capture/illustration, Closet and illustrative shirt try-on**. Accounts, a server, real retailer inventory, checkout and synchronization are not prerequisites for that journey. No approved requirement or current native implementation makes them release gates for this MVP. No service, credential, payment integration or new dependency is introduced by this readiness pass.

Authority: the current [README](../README.md), production `OnYouRootView` navigation, native scan/Closet/store implementations and [combined integration audit](ONYOU_FINAL_GAP_AUDIT.md). The older internal FitCheck catalogue/repository abstractions and fictional demo products are not a commitment to live retailer inventory. Customer-facing branding remains **On You**.

## Required and already implemented

| Current MVP requirement | Existing implementation | Remaining boundary |
|---|---|---|
| Body experience | Native SceneKit viewer, saved textured avatar loading, separate measurement-driven generic model and History. | A manual model does not authorize captured-avatar try-on or prove a person's anatomy. |
| Body capture | Native Object Capture/Photogrammetry, photo/depth admission, guidance, recovery, scale/texture review and local storage. | Real-device capture and dimensional accuracy remain NOT RUN; see [device validation](ONYOU_DEVICE_VALIDATION.md). |
| Local Closet | Garment photo/metadata persistence, import, automatic supported-shirt capture, retakes, reference selection and deletion. | Imported photographs remain photo-only; supported metric capture is not independent physical validation. |
| Illustrative try-on | Existing saved-avatar/supported-shirt admission, connected garment shell, observed front image, inferred rear, rotation, visibility and lifecycle ownership. | Not physical fit, pressure, fabric simulation or a size recommendation. |
| Optional product link | A user-entered HTTP(S) link is retained with a garment; detail presents **View product** only when that link exists (`ClosetGarment`, `AddGarmentView`, `ClosetGarmentDetailView`). | Explicit external navigation, not catalogue search, inventory verification, affiliate attribution or in-app checkout. Core local use needs no link/network. |
| Privacy/reliability | Local stores, explicit scan/photo protection and directory backup exclusion, avatar integrity checks, cancellation, corrupt-data handling and Debug fixture isolation. | Manual measurements/history use separate UserDefaults without an established explicit scan/photo backup/protection guarantee. Distribution gates are in [release readiness](ONYOU_FINAL_RELEASE_READINESS.md). |

## Candidate later work — not approved or scheduled

“Later” below is a dependency assessment, **not** a promise to implement or a product launch commitment. Each needs owner approval, acceptance criteria and privacy/security review before engineering starts.

| Integration | Current status / MVP classification | Dependencies before implementation |
|---|---|---|
| Real retailer inventory | **NOT IMPLEMENTED / NOT REQUIRED / NOT APPROVED.** Fictional internal products must never be promoted into live stock. | Authorized retailer agreement/API, supported regions, truthful variant identifiers, source provenance, update/expiry and unavailable-product rules, usage/image rights and test credentials supplied through an approved secure workflow. |
| Product feeds | **NOT IMPLEMENTED / NOT REQUIRED / NOT APPROVED.** No background feed service is needed by local Closet. | Approved data provider/schema, ingestion ownership, identifier/variant association, refresh/deletion policy, image licensing, outage behavior and operational cost/security review. Do not scrape assets or invent prices/sizes. |
| User accounts | **NOT IMPLEMENTED / NOT REQUIRED / NOT APPROVED.** Current use is local and does not require login. | A justified cross-device/server use case, identity provider decision, consent, recovery/deletion, abuse/security controls, retention and authorized distribution configuration. Do not add authentication merely to gate the offline app. |
| Cross-device synchronization | **NOT IMPLEMENTED / NOT REQUIRED / NOT APPROVED.** Existing local storage is preserved. | Approved account/device trust model, versioned sync contract compatible with current files, conflict/merge/deletion semantics, offline behavior, encryption/access control, quota/cost and independent failure tests. Never silently upload existing body or garment data. |
| Optional cloud backup | **NOT IMPLEMENTED as an app-managed service / NOT REQUIRED / NOT APPROVED.** Platform-managed backup behavior is a separate disclosure/validation question, not an implemented On You cloud service. | Explicit opt-in and data inventory, provider/region/security policy, retention/export/deletion, restore/corruption tests and consent for any body/photo transfer. Reconcile existing scan/photo backup exclusion before changing it. |
| Checkout / shopping links | **Checkout NOT IMPLEMENTED / NOT REQUIRED / NOT APPROVED.** The optional manually entered external link above already works; no new shopping connector is needed. | Owner decision on external referral versus commerce, authorized merchant/offer data, variant/price/availability provenance, return/support responsibilities, legal/App Store review and approved payment/compliance handling if checkout is later required. No fake checkout or availability guarantee. |
| More garment categories | **NOT APPROVED / NOT REQUIRED.** Current automatic geometry/landmark assumptions support reviewed short-sleeved shirts, not an arbitrary garment engine. | Explicit category/pose/measurement definitions, licensed representative assets or model/schema changes where actually needed, independent metrology, geometry/texture/admission/lifecycle tests and reviewed UI guidance. Keep unsupported combinations honest rather than relabeling a tee mesh. |
| Accurate physical fit / sizing | **UNVERIFIED / SEPARATE RESEARCH.** Not a prerequisite for retaining the honest illustrative MVP. | Complete the [fit validation roadmap](ONYOU_FIT_VALIDATION_ROADMAP.md): independent body/garment references, repeatability, material thickness/stretch, drape/contact/motion evidence, approved error budgets and claims review. No unvalidated recommendation or pressure map. |

## Sequencing

1. Review the integrated software and complete supported-device/privacy/distribution gates; do not replace working local features.
2. Validate current capture and geometry against independently measured nonpersonal references before expanding physical claims.
3. Obtain an explicit product decision for any commercial integration, including data rights, dependencies, offline behavior and acceptance criteria.
4. Build only that approved integration, without changing storage/privacy contracts or introducing accounts/cloud/payment as unrelated prerequisites.

There is no missing backend or retailer integration blocking the defined offline MVP. Physical validation and release/distribution approval remain separate, explicit gates.
