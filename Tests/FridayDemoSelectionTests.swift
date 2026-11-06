#if DEBUG
import Foundation
import Metal
import XCTest
@testable import FitCheck

@MainActor
final class FridayDemoSelectionTests: XCTestCase {
    func testEveryCuratedSelectionLoadsItsApprovedMaterialAndRealGPUAsset() async throws {
        let selection = FridayDemoSelection()
        let cases: [(String, String, RendererMaterial, String?)] = [
            ("everyday-tee", "everyday-navy", .navy, nil),
            ("weekend-tee", "weekend-sage", .sage, nil),
            ("geometric-vest", "geometric-vest-navy", .navy, RendererBundledAssetDescriptor.reviewedVest.asset.assetID)
        ]
        for (product, skuPrefix, material, assetID) in cases {
            for (size, label) in [("small", "S"), ("medium", "M")] {
                selection.select(productID: product, sizeID: size)
                let preview = try XCTUnwrap(selection.preview)
                XCTAssertEqual(preview.variantID, "\(skuPrefix)-\(size)")
                XCTAssertEqual(preview.sizeLabel, label)
                XCTAssertEqual(preview.rendererPresentation.initialMaterial, material)
                let model = RendererLabModel(presentation: preview.rendererPresentation)
                let load = model.open(isActive: true)
                await load?.value
                let scene = try XCTUnwrap(model.session)
                let garment = try XCTUnwrap(scene.garment)
                XCTAssertEqual(scene.garmentAssetIdentifier, assetID)
                XCTAssertEqual(garment.color, RendererProceduralAssets.color(for: material))
                let vertices = try XCTUnwrap(garment.vertexBuffer)
                let first = vertices.contents().bindMemory(to: RendererVertex.self, capacity: garment.mesh.vertices.count)
                XCTAssertEqual(first[0].position, garment.mesh.vertices[0].position)
                XCTAssertNotNil(garment.indexBuffer)
                model.close()
                XCTAssertTrue(scene.isDisposed)
                XCTAssertNil(garment.vertexBuffer)
                XCTAssertNil(model.session)
            }
        }
    }

    func testUnsupportedSelectionRemovesPreviousPreviewAndSupportedChoiceRecovers() throws {
        let selection = FridayDemoSelection()
        XCTAssertEqual(selection.preview?.variantID, "everyday-navy-small")
        for (product, size) in [("everyday-tee", "large"), ("archived-tee", "medium"), ("unknown", "small")] {
            selection.select(productID: product, sizeID: size)
            XCTAssertNil(selection.preview, "An invalid combination must not retain a successful old garment")
            XCTAssertNotNil(selection.failure)
            selection.select(productID: "weekend-tee", sizeID: "medium")
            XCTAssertEqual(selection.preview?.variantID, "weekend-sage-medium")
            XCTAssertNil(selection.failure)
        }
    }

    func testCorruptCatalogNeverProducesAReplacementPreview() {
        let selection = FridayDemoSelection(data: Data("not a catalog".utf8))
        XCTAssertNil(selection.preview)
        XCTAssertTrue(selection.products.isEmpty)
        selection.reload()
        XCTAssertNil(selection.preview)
        XCTAssertNotNil(selection.failure)
    }

    func testUnavailableOrUnverifiedCuratedVariantFailsClosedWithoutPartialCollection() throws {
        for mutation in ["availability", "provenance"] {
            var document = try XCTUnwrap(JSONSerialization.jsonObject(with: SyntheticCatalog.data) as? [String: Any])
            var products = try XCTUnwrap(document["products"] as? [[String: Any]])
            if mutation == "availability" {
                var variants = try XCTUnwrap(products[0]["variants"] as? [[String: Any]])
                variants[0]["availability"] = "outOfStock"
                products[0]["variants"] = variants
            } else {
                products[0]["provenance"] = ["source": "retailerProvided", "revision": "sample-v1", "reference": "local-synthetic-fixture"]
            }
            document["products"] = products
            let selection = FridayDemoSelection(data: try JSONSerialization.data(withJSONObject: document))
            XCTAssertNil(selection.preview)
            XCTAssertTrue(selection.products.isEmpty)
            XCTAssertNotNil(selection.failure)
        }
    }
}
#endif
