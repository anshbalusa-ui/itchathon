#if DEBUG
import XCTest
@testable import FitCheck

final class RendererContractTests: XCTestCase {
    func testSceneConfigurationRejectsNonFiniteAndUnsafeFramingValues() {
        let valid = RendererSceneConfiguration.standard
        XCTAssertNoThrow(try valid.validate())

        let invalid = [
            RendererSceneConfiguration(cameraDistance: .nan, verticalFieldOfView: 40, nearClip: 0.05, farClip: 20),
            RendererSceneConfiguration(cameraDistance: .infinity, verticalFieldOfView: 40, nearClip: 0.05, farClip: 20),
            RendererSceneConfiguration(cameraDistance: 3.5, verticalFieldOfView: .infinity, nearClip: 0.05, farClip: 20),
            RendererSceneConfiguration(cameraDistance: 3.5, verticalFieldOfView: 40, nearClip: .nan, farClip: 20),
            RendererSceneConfiguration(cameraDistance: 3.5, verticalFieldOfView: 40, nearClip: 0.05, farClip: .infinity),
            RendererSceneConfiguration(cameraDistance: 0, verticalFieldOfView: 45, nearClip: 0.1, farClip: 20),
            RendererSceneConfiguration(cameraDistance: 3.4, verticalFieldOfView: 0, nearClip: 0.1, farClip: 20),
            RendererSceneConfiguration(cameraDistance: 3.4, verticalFieldOfView: 90, nearClip: 0.1, farClip: 20),
            RendererSceneConfiguration(cameraDistance: 3.4, verticalFieldOfView: 45, nearClip: 3.4, farClip: 20),
            RendererSceneConfiguration(cameraDistance: 3.4, verticalFieldOfView: 45, nearClip: 0.1, farClip: 5),
            RendererSceneConfiguration(cameraDistance: 1.5, verticalFieldOfView: 45, nearClip: 0.1, farClip: 20),
            RendererSceneConfiguration(cameraDistance: 3.4, verticalFieldOfView: 45, nearClip: 0.1, farClip: 20, targetHeight: .nan),
            RendererSceneConfiguration(cameraDistance: 3.4, verticalFieldOfView: 45, nearClip: 0.1, farClip: 20, targetHeight: .infinity),
            RendererSceneConfiguration(cameraDistance: 3.4, verticalFieldOfView: 45, nearClip: 0.1, farClip: 20, targetHeight: -1),
            RendererSceneConfiguration(cameraDistance: 3.4, verticalFieldOfView: 45, nearClip: 0.1, farClip: 20, targetHeight: 1.8),
            RendererSceneConfiguration(cameraDistance: 1, verticalFieldOfView: 45, nearClip: 0.1, farClip: 20),
            RendererSceneConfiguration(cameraDistance: 3.4, verticalFieldOfView: 45, nearClip: 3, farClip: 20),
            RendererSceneConfiguration(cameraDistance: 3.4, verticalFieldOfView: 45, nearClip: 0.1, farClip: 3.5),
            RendererSceneConfiguration(cameraDistance: 3.4, verticalFieldOfView: 20, nearClip: 0.1, farClip: 20),
            RendererSceneConfiguration(cameraDistance: .greatestFiniteMagnitude, verticalFieldOfView: 40, nearClip: 0.05, farClip: 20)
        ]
        for configuration in invalid {
            XCTAssertThrowsError(try configuration.validate())
        }
    }


    func testOrbitRemainsFiniteBoundedAndWrappedForExtremeInput() {
        var orbit = RendererOrbit.initial
        orbit.rotate(horizontal: .greatestFiniteMagnitude, vertical: .greatestFiniteMagnitude)
        XCTAssertTrue(orbit.yaw.isFinite)
        XCTAssertTrue(orbit.pitch.isFinite)
        XCTAssertGreaterThanOrEqual(orbit.yaw, -.pi)
        XCTAssertLessThanOrEqual(orbit.yaw, .pi)
        XCTAssertEqual(orbit.pitch, RendererOrbit.maximumPitch, accuracy: 0.0001)

        orbit.rotate(horizontal: -.greatestFiniteMagnitude, vertical: -.greatestFiniteMagnitude)
        XCTAssertTrue(orbit.yaw.isFinite)
        XCTAssertEqual(orbit.pitch, -RendererOrbit.maximumPitch, accuracy: 0.0001)

        let beforeInvalidInput = orbit
        orbit.rotate(horizontal: .infinity, vertical: .nan)
        XCTAssertEqual(orbit, beforeInvalidInput)
    }

    func testOrbitWrapsAndResetReturnsToStableInitialState() {
        var orbit = RendererOrbit.initial
        orbit.rotate(horizontal: 4 * .pi + 0.25, vertical: 100)
        XCTAssertEqual(orbit.yaw, .pi / 8 + 0.25, accuracy: 0.0001)
        XCTAssertEqual(orbit.pitch, RendererOrbit.maximumPitch, accuracy: 0.0001)

        orbit.reset()
        XCTAssertEqual(orbit, RendererOrbit.initial)
        orbit.rotate(horizontal: -2 * .pi - 0.5, vertical: -0.2)
        let first = orbit
        orbit.reset()
        orbit.rotate(horizontal: -2 * .pi - 0.5, vertical: -0.2)
        XCTAssertEqual(orbit, first)
    }


    func testOnlyKnownFixtureAssetsWithExactRoleAndMetadataAreSupported() {
        XCTAssertNoThrow(try RendererAssetDescriptor.mannequinFixture.validate(for: .mannequin))
        XCTAssertNoThrow(try RendererAssetDescriptor.garmentFixture.validate(for: .garment))

        let mannequin = RendererAssetDescriptor.mannequinFixture
        let garment = RendererAssetDescriptor.garmentFixture
        let invalid = [
            asset(mannequin, role: .garment),
            asset(garment, role: .mannequin),
            asset(mannequin, schemaVersion: 2),
            asset(mannequin, assetID: "unrecognized-geometry"),
            asset(mannequin, revision: 2),
            asset(mannequin, coordinateSystem: "left-handed:+Y-up:+Z-forward"),
            asset(mannequin, unit: "centimetre"),
            asset(mannequin, origin: "centre-of-mass"),
            asset(mannequin, scale: 0),
            asset(mannequin, scale: .nan),
            asset(mannequin, source: .remote),
            asset(mannequin, source: .userImport),
            asset(mannequin, provenance: .unknown),
            asset(mannequin, provenance: .retailer),
            asset(mannequin, license: .commercial),
            asset(mannequin, license: .unknown),
            asset(mannequin, isLocallyOwned: false),
            asset(garment, productID: "catalog-product"),
            asset(garment, variantID: "catalog-variant"),
            asset(mannequin, materialModel: .unsupported),
            asset(mannequin, personalized: true),
            asset(mannequin, rendererCapability: "unapproved-renderer"),
            asset(mannequin, type: .usdz)
        ]
        for descriptor in invalid {
            XCTAssertThrowsError(try descriptor.validate(for: descriptor.role))
        }
    }

    private func asset(
        _ base: RendererAssetDescriptor,
        type: RendererAssetType? = nil,
        role: RendererAssetRole? = nil,
        schemaVersion: Int? = nil,
        assetID: String? = nil,
        revision: Int? = nil,
        coordinateSystem: String? = nil,
        unit: String? = nil,
        origin: String? = nil,
        scale: Float? = nil,
        source: RendererAssetSource? = nil,
        provenance: RendererAssetProvenance? = nil,
        license: RendererAssetLicense? = nil,
        isLocallyOwned: Bool? = nil,
        productID: String? = nil,
        variantID: String? = nil,
        materialModel: RendererMaterialModel? = nil,
        rendererCapability: String? = nil,
        personalized: Bool? = nil
    ) -> RendererAssetDescriptor {
        RendererAssetDescriptor(
            type: type ?? base.type,
            role: role ?? base.role,
            schemaVersion: schemaVersion ?? base.schemaVersion,
            assetID: assetID ?? base.assetID,
            revision: revision ?? base.revision,
            coordinateSystem: coordinateSystem ?? base.coordinateSystem,
            unit: unit ?? base.unit,
            origin: origin ?? base.origin,
            scale: scale ?? base.scale,
            source: source ?? base.source,
            provenance: provenance ?? base.provenance,
            license: license ?? base.license,
            isLocallyOwned: isLocallyOwned ?? base.isLocallyOwned,
            productID: productID ?? base.productID,
            variantID: variantID ?? base.variantID,
            materialModel: materialModel ?? base.materialModel,
            rendererCapability: rendererCapability ?? base.rendererCapability,
            personalized: personalized ?? base.personalized
        )
    }
}
#endif
