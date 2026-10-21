# Minimum authorized retailer catalog contract

This is the information required before integrating Ben's business. No store platform, inventory, price, measurements, image rights, API permission, or fit capability has been verified. The offline `sample-studio` retailer and every sample product are fictional.

## Obtain and review before adapter work

| Area | Required retailer information / acceptance condition |
| --- | --- |
| Business/platform | Legal retailer identity, approved display/brand names, storefront platform and domain, store/tenant identifiers, technical contact, supported markets. Do not assume Shopify or scrape a public website. |
| API authorization | Written permission and exact allowed fields/use, authorized API/export format, version, rate limits, pagination, webhooks/cache rules, sandbox data and access revocation. Secrets belong in approved infrastructure, never application source or bundled JSON. No live connection is implemented here. |
| Stable identity | Product and purchasable-variant/SKU identifiers, retailer namespace, case sensitivity, ID reuse/deletion rules, and mappings across API versions. Titles, array positions, S/M/L labels, and generated UUIDs are not stable retailer IDs. |
| Options | Which color/size combinations actually exist, stable option IDs and display labels/order, color swatch values if genuinely supplied, category semantics. Do not generate a Cartesian product of sizes/colors or infer size ordering/grading from labels. |
| Descriptions | Approved titles, descriptions, materials/care if supplied, language/locale and revision. Missing copy remains missing; do not turn a generic concept into a claim about fabric, cut, sustainability or quality. |
| Money | ISO currency code, exact minor-unit price per market and variant, whether a product-level price is only a starting/display price, tax inclusion, discount/compare-at semantics, effective dates and updates. Unknown variant price stays unknown; it does not silently inherit a starting price. |
| Inventory | Meaning of purchasable, sold out, unknown, discontinued, preorders/backorders and product removal; source freshness/version and whether a lookup reserves stock. Current selection reserves nothing and does not create a cart/order. Unknown is not available. |
| Actual garment measurements | Finished-garment basis, exact per-variant values, units, named measurement locations/protocol, source/reference, specification revision and date. Distinguish flat chest width from circumference and garment length from body length. Never derive dimensions from size labels or scale one shirt into other sizes. |
| Body recommendation charts | Identify separately and preserve their meaning. They are not physical finished-garment dimensions and cannot populate `CatalogFinishedMeasurements`. No body-measurement entry or size recommendation is implemented in this catalog. |
| Product specifications | Authoritative specification version, what changed, applicable SKU/color/material versions and correction policy. A revision/source string is provenance, not independent measurement validation. |
| Media rights | Original product media references, approved alt text, owner/license, commercial display permission, caching/offline/attribution and expiry rules. Photograph rights do not automatically grant 3D asset, derivative garment-model or simulation rights. No retailer imagery was downloaded. |
| Availability/errors | Distinguish absent product, temporarily unavailable source, invalid/unsupported data, unauthorized access and retriable transport failure. Do not turn a failed request into an empty successful collection or fake stock. |
| Privacy/operations | Approved logging/data retention, nonsensitive diagnostics, customer-data handling and consent. Catalog integration must not receive raw RGB, depth, masks, landmarks, body measurements, or camera credentials. |

## Current adapter boundary

`CatalogRepository` exposes async listing, scoped product lookup and color/size variant lookup. `OfflineCatalogRepository` validates a versioned immutable snapshot before returning any products. Invalid/duplicate data fails as a whole, preserving identity correctness rather than silently selecting one record. The UI does not decode retailer payloads or know transport details.

A future authorized adapter maps the real contract into these domain values, preserving missing data and provenance. A remote media loader, pagination or other transport feature should be added only when required by that reviewed integration; no empty network layer was added now. Remote media references can be represented, but this offline presentation does not fetch them.

All samples are synthetic. Their availability and prices exercise UI states only and are not retailer offers. No sample has product photos or finished dimensions. The generic SF Symbol T-shirt is an interface placeholder, explicitly labelled as missing photography, not a representation of the actual garment.

## Device and future-service responsibilities

- Device: browsing/selection state, accessible presentation, local validated catalog cache if later authorized, and all sensitive scan/identifying avatar data. This segment reads no scan, avatar, or measurement storage.
- Future authorized service: retailer credentials/access, catalog/SKU normalization, authoritative price/stock/specification versions, media entitlement and operational rate/cache policy. Account or synchronization design remains separate.
- Core contract: plain scalar/Codable/Sendable catalog data, explicit units and source, no Apple camera or SwiftUI objects. A future Android adapter can use the same meanings; no Android code or sensor parity is implied.

## Segment boundaries

No cloud/database, accounts, checkout/cart, live inventory, avatar generation, clothing rendering, fit prediction or real retailer integration is included. Missing avatar capability remains unavailable. PR #10's physical scanner blockers are unchanged; Segment 1B is not run or approved by this independent catalog work.
