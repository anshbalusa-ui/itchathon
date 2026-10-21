#if DEBUG
import Foundation

/// World space uses metres, +Y up, a right-handed frame, and +Z as mannequin front.
enum RendererCoordinates {
    static let worldUnit = "metre"
    static let upAxis = "+Y"
    static let handedness = "right-handed"
    static let forwardAxis = "+Z"
    static let meshOrigin = "floor-centred"
    static let pivotHeight: Float = 0.9
    static let fixtureScale: Float = 1
    static let convention = "\(handedness):\(upAxis)-up:\(forwardAxis)-forward"
}

enum RendererFailure: Error, Equatable, LocalizedError {
    case invalidConfiguration
    case unsupportedAsset
    case missingAsset
    case graphicsUnavailable
    case sceneCreationFailed

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration: "The scene configuration cannot safely frame this fixture."
        case .unsupportedAsset: "This asset is not supported by the generic fixture renderer."
        case .missingAsset: "No garment asset is available."
        case .graphicsUnavailable: "A compatible graphics device is unavailable."
        case .sceneCreationFailed: "The 3D scene could not be created. You can retry."
        }
    }
}

struct RendererSceneConfiguration: Equatable {
    var cameraDistance: Float
    var verticalFieldOfView: Float
    var nearClip: Float
    var farClip: Float
    var targetHeight: Float = RendererCoordinates.pivotHeight

    static let standard = RendererSceneConfiguration(
        cameraDistance: 3.4,
        verticalFieldOfView: 45,
        nearClip: 0.1,
        farClip: 20,
        targetHeight: RendererCoordinates.pivotHeight
    )

    func validate() throws {
        guard cameraDistance.isFinite, verticalFieldOfView.isFinite,
              nearClip.isFinite, farClip.isFinite, targetHeight.isFinite,
              cameraDistance > 0, cameraDistance <= 20,
              verticalFieldOfView >= 20, verticalFieldOfView <= 70,
              nearClip >= 0.01, nearClip < cameraDistance,
              farClip > cameraDistance + 1.9, farClip <= 100,
              targetHeight >= 0.25, targetHeight <= 1.55 else {
            throw RendererFailure.invalidConfiguration
        }
        // A conservative sphere contains the fixture at every permitted yaw/pitch.
        // Reserve the narrower field of a 0.75-aspect viewport, plus a framing margin.
        let largestVerticalExtent = max(targetHeight, 1.8 - targetHeight)
        let radius = sqrt(largestVerticalExtent * largestVerticalExtent + 0.4 * 0.4)
        let halfFOVRadians = atan(tan(verticalFieldOfView * .pi / 360) * 0.75)
        let requiredDistance = radius / sin(halfFOVRadians) * 1.02
        guard requiredDistance.isFinite, cameraDistance >= requiredDistance,
              nearClip < cameraDistance - radius else {
            throw RendererFailure.invalidConfiguration
        }
    }
}

struct RendererOrbit: Equatable {
    static let maximumPitch: Float = .pi / 8
    static let initial = RendererOrbit(yaw: .pi / 8, pitch: 0)

    private(set) var yaw: Float
    private(set) var pitch: Float

    init(yaw: Float = .pi / 8, pitch: Float = 0) {
        self.yaw = Self.wrapped(yaw.isFinite ? yaw : .pi / 8)
        self.pitch = pitch.isFinite ? min(max(pitch, -Self.maximumPitch), Self.maximumPitch) : 0
    }

    mutating func rotate(horizontal: Float, vertical: Float) {
        guard horizontal.isFinite, vertical.isFinite else { return }
        // Reduce before addition so even greatest-finite deltas cannot overflow.
        yaw = Self.wrapped(yaw + horizontal.truncatingRemainder(dividingBy: 2 * .pi))
        let boundedVertical = min(max(vertical, -2 * Self.maximumPitch), 2 * Self.maximumPitch)
        pitch = min(max(pitch + boundedVertical, -Self.maximumPitch), Self.maximumPitch)
    }

    mutating func reset() { self = .initial }

    private static func wrapped(_ angle: Float) -> Float {
        let remainder = angle.truncatingRemainder(dividingBy: 2 * .pi)
        if remainder > .pi { return remainder - 2 * .pi }
        if remainder < -.pi { return remainder + 2 * .pi }
        return remainder
    }
}

enum RendererMaterial: String, CaseIterable, Identifiable {
    case navy, stone, sage

    var id: String { rawValue }
    var title: String {
        switch self {
        case .navy: "Navy"
        case .stone: "Stone"
        case .sage: "Sage"
        }
    }
}

/// Scalar presentation settings shared by the renderer lab and catalog illustrations.
struct RendererPresentation: Equatable, Hashable {
    let navigationTitle: String
    let context: String?
    let initialMaterial: RendererMaterial
    let allowsMaterialChanges: Bool

    init(
        navigationTitle: String,
        context: String? = nil,
        initialMaterial: RendererMaterial = .navy,
        allowsMaterialChanges: Bool = true
    ) {
        self.navigationTitle = navigationTitle
        self.context = context
        self.initialMaterial = initialMaterial
        self.allowsMaterialChanges = allowsMaterialChanges
    }

    static let lab = RendererPresentation(navigationTitle: "3D Renderer Lab")
}

struct RendererAppearance: Equatable {
    var garmentVisible = true
    var material: RendererMaterial = .navy

    mutating func reset(to material: RendererMaterial = .navy) {
        self = RendererAppearance(garmentVisible: true, material: material)
    }
}

enum RendererAssetRole: String, Equatable { case mannequin, garment }
enum RendererAssetType: String, Equatable { case proceduralFixture, usdz, unknown }
enum RendererAssetSource: String, Equatable { case bundledFixture, remote, userImport, unknown }
enum RendererAssetProvenance: String, Equatable { case firstPartyFixture, retailer, userProvided, unknown }
enum RendererAssetLicense: String, Equatable { case internalDevelopmentOnly, commercial, unknown }
enum RendererMaterialModel: String, Equatable { case solidColorLambert, unlit, unsupported }

/// Metadata is descriptive only: it cannot authorize personalized geometry or grant rights.
struct RendererAssetDescriptor: Equatable {
    let type: RendererAssetType
    let role: RendererAssetRole
    let schemaVersion: Int
    let assetID: String
    let revision: Int
    let coordinateSystem: String
    let unit: String
    let origin: String
    let scale: Float
    let source: RendererAssetSource
    let provenance: RendererAssetProvenance
    let license: RendererAssetLicense
    let isLocallyOwned: Bool
    let productID: String?
    let variantID: String?
    let materialModel: RendererMaterialModel
    let rendererCapability: String
    let personalized: Bool

    static let mannequinFixture = RendererAssetDescriptor(
        type: .proceduralFixture, role: .mannequin, schemaVersion: 1,
        assetID: "fitcheck.generic-mannequin", revision: 1,
        coordinateSystem: RendererCoordinates.convention, unit: RendererCoordinates.worldUnit,
        origin: RendererCoordinates.meshOrigin, scale: RendererCoordinates.fixtureScale, source: .bundledFixture,
        provenance: .firstPartyFixture, license: .internalDevelopmentOnly,
        isLocallyOwned: true, productID: nil, variantID: nil,
        materialModel: .solidColorLambert, rendererCapability: "fitcheck.r0.metal.v1", personalized: false
    )
    static let garmentFixture = RendererAssetDescriptor(
        type: .proceduralFixture, role: .garment, schemaVersion: 1,
        assetID: "fitcheck.illustrative-garment", revision: 1,
        coordinateSystem: RendererCoordinates.convention, unit: RendererCoordinates.worldUnit,
        origin: RendererCoordinates.meshOrigin, scale: RendererCoordinates.fixtureScale, source: .bundledFixture,
        provenance: .firstPartyFixture, license: .internalDevelopmentOnly,
        isLocallyOwned: true, productID: nil, variantID: nil,
        materialModel: .solidColorLambert, rendererCapability: "fitcheck.r0.metal.v1", personalized: false
    )

    func validate(for expectedRole: RendererAssetRole) throws {
        let expected = expectedRole == .mannequin ? Self.mannequinFixture : Self.garmentFixture
        guard type == .proceduralFixture, role == expectedRole,
              schemaVersion == 1, assetID == expected.assetID, revision == expected.revision,
              coordinateSystem == expected.coordinateSystem, unit == expected.unit,
              origin == expected.origin, scale.isFinite, scale == expected.scale,
              source == .bundledFixture, provenance == .firstPartyFixture,
              license == .internalDevelopmentOnly, isLocallyOwned,
              materialModel == .solidColorLambert, rendererCapability == expected.rendererCapability, !personalized,
              productID == nil, variantID == nil else {
            // USDZ remains unsupported until an approved, audited loader exists.
            throw RendererFailure.unsupportedAsset
        }
    }
}
#endif
