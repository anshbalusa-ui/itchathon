#if DEBUG
import Foundation
import Metal
import MetalKit
import UIKit
import simd

struct RendererCamera {
    var position: SIMD3<Float>
    var target: SIMD3<Float>
    var nearClip: Float
    var farClip: Float
    var verticalFieldOfView: Float
}

@MainActor
final class RendererRenderObject {
    private(set) var isEnabled = true
    private(set) var color: SIMD4<Float>
    let mesh: RendererMesh
    private(set) var vertexBuffer: MTLBuffer?
    private(set) var indexBuffer: MTLBuffer?
    private(set) var clearanceBuffer: MTLBuffer?

    init(mesh: RendererMesh, color: SIMD4<Float>, device: MTLDevice, usesClearance: Bool = true) throws {
        self.mesh = mesh
        self.color = color
        guard !mesh.vertices.isEmpty, !mesh.indices.isEmpty,
              let vertices = device.makeBuffer(bytes: mesh.vertices,
                                               length: mesh.vertices.count * MemoryLayout<RendererVertex>.stride,
                                               options: .storageModeShared),
              let indices = device.makeBuffer(bytes: mesh.indices,
                                              length: mesh.indices.count * MemoryLayout<UInt16>.stride,
                                              options: .storageModeShared) else {
            throw RendererFailure.sceneCreationFailed
        }
        vertexBuffer = vertices
        indexBuffer = indices
        if usesClearance, let clearance = mesh.sampleClearance {
            guard clearance.count == mesh.vertices.count,
                  clearance.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 0.1 }),
                  let buffer = device.makeBuffer(bytes: clearance,
                                                 length: clearance.count * MemoryLayout<Float>.stride,
                                                 options: .storageModeShared) else {
                throw RendererFailure.invalidConfiguration
            }
            clearanceBuffer = buffer
        }
    }

    func update(color: SIMD4<Float>, isEnabled: Bool) {
        self.color = color
        self.isEnabled = isEnabled
    }

    func releaseBuffers() {
        vertexBuffer = nil
        indexBuffer = nil
        clearanceBuffer = nil
    }
}

@MainActor
final class RendererSceneSession: NSObject, MTKViewDelegate {
    private struct VertexUniforms {
        var modelViewProjection: simd_float4x4
        var model: simd_float4x4
        var hasClearance: UInt32
    }

    private struct FragmentUniforms {
        var color: SIMD4<Float>
        var regionMinimum: SIMD4<Float>
        var regionMaximum: SIMD4<Float>
        var mapEnabled: UInt32
    }

    let id = UUID()
    let view: MTKView
    let mannequin: RendererRenderObject
    private(set) var garment: RendererRenderObject?
    private(set) var garmentFailure: RendererFailure?
    private(set) var garmentAssetIdentifier: String?
    private(set) var isDisposed = false
    private(set) var modelTransform = matrix_identity_float4x4
    private(set) var camera: RendererCamera
    private(set) var viewProjection = matrix_identity_float4x4
    var onFailure: (@MainActor (RendererFailure) -> Void)?

    private let device: MTLDevice
    private var commandQueue: MTLCommandQueue?
    private(set) var pipelineState: MTLRenderPipelineState?
    private var depthState: MTLDepthStencilState?
    private let isSyntheticGeometryScene: Bool
    let isHumanAvatarScene: Bool
    private let isMeasurementAvatarScene: Bool
    private let measurementBounds: (minimum: SIMD3<Float>, maximum: SIMD3<Float>)?
    private var modestyGarment: RendererRenderObject?
    private var humanRegion = HumanBodyRegion.whole
    private var humanMapVisible = false
    private var cachedGarment: RendererRenderObject?
    private let configuration: RendererSceneConfiguration
    private let fittedSurfaceRadius: Float?
    private var orbit = RendererOrbit.initial
    private var appearance = RendererAppearance()
    private var isProceduralGarmentCached = false

    convenience init(configuration: RendererSceneConfiguration = .standard,
                      mannequinAsset: RendererAssetDescriptor = .mannequinFixture,
                      garmentAsset: RendererAssetDescriptor? = .garmentFixture) throws {
        try self.init(configuration: configuration, mannequinAsset: mannequinAsset, garmentAsset: garmentAsset,
                      generatedMesh: nil)
    }

    convenience init(human: HumanShowcaseMeshes, garment: HumanShowcaseGarment) throws {
        try self.init(configuration: .standard, mannequinAsset: .mannequinFixture, garmentAsset: nil,
                      generatedMesh: nil, human: human, humanGarment: garment)
    }

    /// Editable demo dimensions have their own authority; never a scan/artifact promotion.
    convenience init(measurementAvatar: MeasurementAvatarResult) throws {
        var configuration = RendererSceneConfiguration.standard
        configuration.targetHeight = (measurementAvatar.body.minimum.y + measurementAvatar.body.maximum.y) * 0.5
        configuration.cameraDistance = 4.5
        try self.init(configuration: configuration, mannequinAsset: .mannequinFixture, garmentAsset: nil,
                      generatedMesh: nil, measurementAvatar: measurementAvatar)
    }

    convenience init(geometry: GeometryResult, fitSurface: Bool = false) throws {
        let mesh = try GeometryRendererAdapter.mesh(from: geometry)
        try self.init(configuration: .standard, mannequinAsset: .mannequinFixture, garmentAsset: nil,
                      generatedMesh: mesh, fitSurface: fitSurface)
    }

    /// Uses the admitted disk-decoded arrays; it cannot mint GeometryResult authority.
    convenience init(artifact: VerifiedSyntheticArtifact) throws {
        let mesh = try GeometryRendererAdapter.mesh(from: artifact)
        try self.init(configuration: .standard, mannequinAsset: .mannequinFixture, garmentAsset: nil,
                      generatedMesh: mesh)
    }

    convenience init(replay: ReplayGeometryResult, fitSurface: Bool = false) throws {
        let mesh = try GeometryRendererAdapter.mesh(from: replay)
        try self.init(configuration: .standard, mannequinAsset: .mannequinFixture, garmentAsset: nil,
                      generatedMesh: mesh, fitSurface: fitSurface)
    }

    private init(configuration: RendererSceneConfiguration, mannequinAsset: RendererAssetDescriptor,
                 garmentAsset: RendererAssetDescriptor?, generatedMesh: RendererMesh?, fitSurface: Bool = false,
                 human: HumanShowcaseMeshes? = nil, humanGarment: HumanShowcaseGarment? = nil,
                 measurementAvatar: MeasurementAvatarResult? = nil) throws {
        try configuration.validate()
        let sourceCount = (human == nil ? 0 : 1) + (generatedMesh == nil ? 0 : 1) + (measurementAvatar == nil ? 0 : 1)
        guard sourceCount <= 1 else { throw RendererFailure.invalidConfiguration }
        if sourceCount == 0 { try mannequinAsset.validate(for: .mannequin) }
        if fitSurface {
            guard let generatedMesh else { throw RendererFailure.invalidConfiguration }
            // Frame only admitted geometry. The orbit pivot and exact CPU/GPU
            // vertices stay unchanged; this sphere contains every allowed rotation.
            let pivot = SIMD3<Float>(0, configuration.targetHeight, 0)
            let extent = simd_max(simd_abs(generatedMesh.minimum - pivot),
                                  simd_abs(generatedMesh.maximum - pivot))
            let radius = simd_length(extent)
            guard radius.isFinite, radius > 0 else { throw RendererFailure.invalidConfiguration }
            fittedSurfaceRadius = radius
        } else {
            fittedSurfaceRadius = nil
        }
        guard let device = MTLCreateSystemDefaultDevice() else { throw RendererFailure.graphicsUnavailable }
        guard let queue = device.makeCommandQueue() else { throw RendererFailure.graphicsUnavailable }
        let view = MTKView(frame: .zero, device: device)
        view.colorPixelFormat = .bgra8Unorm_srgb
        view.depthStencilPixelFormat = .depth32Float
        view.clearColor = MTLClearColor(red: 0.94, green: 0.94, blue: 0.94, alpha: 1)
        view.enableSetNeedsDisplay = true
        view.isPaused = true
        view.framebufferOnly = true
        self.configuration = configuration
        self.device = device
        self.commandQueue = queue
        self.view = view
        self.isSyntheticGeometryScene = generatedMesh != nil
        self.isHumanAvatarScene = human != nil || measurementAvatar != nil
        self.isMeasurementAvatarScene = measurementAvatar != nil
        if let measurementAvatar {
            measurementBounds = (
                simd_min(measurementAvatar.body.minimum, simd_min(measurementAvatar.shirt.minimum, measurementAvatar.shorts.minimum)),
                simd_max(measurementAvatar.body.maximum, simd_max(measurementAvatar.shirt.maximum, measurementAvatar.shorts.maximum))
            )
        } else {
            measurementBounds = nil
        }
        self.camera = RendererCamera(position: SIMD3<Float>(0, configuration.targetHeight, configuration.cameraDistance),
                                     target: SIMD3<Float>(0, configuration.targetHeight, 0),
                                     nearClip: configuration.nearClip, farClip: configuration.farClip,
                                     verticalFieldOfView: configuration.verticalFieldOfView)
        let humanBody = human?.body ?? measurementAvatar?.body
        mannequin = try RendererRenderObject(mesh: humanBody ?? generatedMesh ?? RendererProceduralAssets.mannequin(),
                                            color: humanBody != nil ? SIMD4<Float>(0.70, 0.72, 0.74, 1)
                                                : generatedMesh == nil ? SIMD4<Float>(0.68, 0.65, 0.60, 1)
                                                : SIMD4<Float>(0.34, 0.49, 0.39, 1), device: device)
        if let measurementAvatar {
            modestyGarment = try RendererRenderObject(mesh: measurementAvatar.shorts, color: SIMD4<Float>(0.32, 0.35, 0.38, 1),
                                                      device: device, usesClearance: false)
            garment = try RendererRenderObject(mesh: measurementAvatar.shirt, color: RendererProceduralAssets.color(for: .navy),
                                               device: device, usesClearance: false)
            garmentAssetIdentifier = "demo.measurement-shaped-shirt"
        } else if let human {
            guard let humanGarment else { throw RendererFailure.invalidConfiguration }
            modestyGarment = try RendererRenderObject(mesh: human.shorts, color: SIMD4<Float>(0.32, 0.35, 0.38, 1),
                                                      device: device, usesClearance: false)
            let mesh = humanGarment == .shirt ? human.shirt : human.vest
            garment = try RendererRenderObject(mesh: mesh, color: RendererProceduralAssets.color(for: .navy), device: device)
            garmentAssetIdentifier = humanGarment.assetIdentifier
        } else if generatedMesh == nil, let garmentAsset {
            do {
                try garmentAsset.validate(for: .garment)
                cachedGarment = try RendererRenderObject(mesh: RendererProceduralAssets.garment(),
                                                         color: RendererProceduralAssets.color(for: .navy), device: device)
                isProceduralGarmentCached = true
                garment = cachedGarment
            } catch {
                garmentFailure = (error as? RendererFailure) ?? .sceneCreationFailed
            }
        } else if generatedMesh == nil {
            garmentFailure = .missingAsset
        }
        do {
            let source = Self.shaderSource
            let library = try device.makeLibrary(source: source, options: nil)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "rendererVertex")
            descriptor.fragmentFunction = library.makeFunction(name: "rendererFragment")
            descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
            descriptor.depthAttachmentPixelFormat = view.depthStencilPixelFormat
            pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
            let depth = MTLDepthStencilDescriptor()
            depth.depthCompareFunction = .less
            depth.isDepthWriteEnabled = true
            depthState = device.makeDepthStencilState(descriptor: depth)
            guard depthState != nil else { throw RendererFailure.sceneCreationFailed }
        } catch {
            mannequin.releaseBuffers()
            cachedGarment?.releaseBuffers()
            modestyGarment?.releaseBuffers()
            throw (error as? RendererFailure) ?? RendererFailure.graphicsUnavailable
        }
        super.init()
        view.delegate = self
        updateTransforms(aspect: 1)
    }
    var hasSyntheticGeometry: Bool { isSyntheticGeometryScene }

    func apply(orbit: RendererOrbit, appearance: RendererAppearance) {
        guard !isDisposed else { return }
        self.orbit = orbit
        self.appearance = appearance
        let yaw = simd_quatf(angle: orbit.yaw, axis: SIMD3<Float>(0, 1, 0))
        let pitch = simd_quatf(angle: orbit.pitch, axis: SIMD3<Float>(1, 0, 0))
        modelTransform = Self.translation(SIMD3<Float>(0, configuration.targetHeight, 0)) *
            simd_float4x4(yaw * pitch) * Self.translation(SIMD3<Float>(0, -configuration.targetHeight, 0))
        mannequin.update(color: isHumanAvatarScene ? SIMD4<Float>(0.70, 0.72, 0.74, 1)
                         : isSyntheticGeometryScene ? SIMD4<Float>(0.34, 0.49, 0.39, 1)
                         : SIMD4<Float>(0.68, 0.65, 0.60, 1), isEnabled: true)
        garment?.update(color: RendererProceduralAssets.color(for: appearance.material), isEnabled: appearance.garmentVisible)
        updateTransforms(aspect: viewportAspect)
        view.setNeedsDisplay()
    }

    func applyHuman(orbit: RendererOrbit, appearance: RendererAppearance,
                    region: HumanBodyRegion, mapVisible: Bool) throws {
        guard !isDisposed, isHumanAvatarScene, !isMeasurementAvatarScene else { throw RendererFailure.unsupportedAsset }
        humanRegion = region
        humanMapVisible = mapVisible
        apply(orbit: orbit, appearance: appearance)
    }

    func replaceGarment(asset: RendererAssetDescriptor?) throws {

        guard !isDisposed else { throw RendererFailure.sceneCreationFailed }
        guard !isSyntheticGeometryScene, !isHumanAvatarScene else { throw RendererFailure.unsupportedAsset }
        guard let asset else {
            clearGarment()
            garmentFailure = .missingAsset
            view.setNeedsDisplay()
            return
        }
        do {
            try asset.validate(for: .garment)
            if !isProceduralGarmentCached {
                let old = cachedGarment
                cachedGarment = try RendererRenderObject(mesh: RendererProceduralAssets.garment(),
                                                         color: RendererProceduralAssets.color(for: appearance.material), device: device)
                isProceduralGarmentCached = true
                if let old, old !== garment { old.releaseBuffers() }
            }
            if let current = garment, current !== cachedGarment { current.releaseBuffers() }
            garment = cachedGarment
            garmentAssetIdentifier = nil
            garment?.update(color: RendererProceduralAssets.color(for: appearance.material), isEnabled: appearance.garmentVisible)
            garmentFailure = nil
            view.setNeedsDisplay()
        } catch {
            clearGarment()
            garmentFailure = (error as? RendererFailure) ?? .sceneCreationFailed
            view.setNeedsDisplay()
            throw garmentFailure!
        }
    }
    func installGarment(_ asset: RendererLoadedGarment) throws {

        guard !isDisposed else { throw RendererFailure.sceneCreationFailed }
        guard !isSyntheticGeometryScene, !isHumanAvatarScene else { throw RendererFailure.unsupportedAsset }
        try asset.descriptor.validate()
        guard asset.descriptor.asset.type == .bundledMeshPackage,
              asset.descriptor.asset.role == .garment,
              !asset.descriptor.asset.personalized else {
            throw RendererFailure.unsupportedAsset
        }
        let imported = try RendererRenderObject(mesh: asset.mesh,
                                                color: RendererProceduralAssets.color(for: appearance.material),
                                                device: device)
        if let current = garment, current !== cachedGarment { current.releaseBuffers() }
        cachedGarment?.releaseBuffers()
        cachedGarment = nil
        isProceduralGarmentCached = false
        garment = imported
        garmentAssetIdentifier = asset.descriptor.asset.assetID
        garmentFailure = nil
        imported.update(color: RendererProceduralAssets.color(for: appearance.material),
                        isEnabled: appearance.garmentVisible)
        view.setNeedsDisplay()
    }

    func clearGarment() {
        guard !isDisposed else { return }
        if let current = garment, current !== cachedGarment { current.releaseBuffers() }
        cachedGarment?.releaseBuffers()
        garment = nil
        cachedGarment = nil
        isProceduralGarmentCached = false
        garmentAssetIdentifier = nil
        garmentFailure = nil
        view.setNeedsDisplay()
    }

    func dispose() {
        guard !isDisposed else { return }
        isDisposed = true
        view.isPaused = true
        view.delegate = nil
        view.releaseDrawables()
        onFailure = nil
        commandQueue = nil
        pipelineState = nil
        depthState = nil
        mannequin.releaseBuffers()
        modestyGarment?.releaseBuffers()
        modestyGarment = nil
        if let garment, garment !== cachedGarment { garment.releaseBuffers() }
        cachedGarment?.releaseBuffers()
        garment = nil
        cachedGarment = nil
        garmentAssetIdentifier = nil
        isProceduralGarmentCached = false
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        guard !isDisposed else { return }
        let aspect = size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0
            ? Float(size.width / size.height) : 1
        updateTransforms(aspect: aspect)
        view.setNeedsDisplay()
    }

    func draw(in view: MTKView) {
        guard !isDisposed else { return }
        guard let queue = commandQueue, let pipeline = pipelineState, let depth = depthState,
              let mannequinVertices = mannequin.vertexBuffer, mannequin.indexBuffer != nil else {
            onFailure?(.sceneCreationFailed)
            return
        }
        // An offscreen/background view can legitimately have no drawable.
        guard let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable else { return }
        guard let command = queue.makeCommandBuffer(),
              let encoder = command.makeRenderCommandEncoder(descriptor: pass) else {
            onFailure?(.graphicsUnavailable)
            return
        }
        encoder.setRenderPipelineState(pipeline)
        encoder.setDepthStencilState(depth)
        encoder.setVertexBuffer(mannequinVertices, offset: 0, index: 0)
        encode(object: mannequin, encoder: encoder)
        if let cover = modestyGarment, let vertices = cover.vertexBuffer, cover.indexBuffer != nil {
            encoder.setVertexBuffer(vertices, offset: 0, index: 0)
            encode(object: cover, encoder: encoder)
        }
        if let garment, garment.isEnabled, let vertices = garment.vertexBuffer, garment.indexBuffer != nil {
            encoder.setVertexBuffer(vertices, offset: 0, index: 0)
            encode(object: garment, encoder: encoder)
        }
        encoder.endEncoding()
        command.present(drawable)
        command.addCompletedHandler { [weak self] buffer in
            guard buffer.status == .error, let self else { return }
            Task { @MainActor [weak self] in
                guard let self, !self.isDisposed else { return }
                self.onFailure?(.graphicsUnavailable)
            }
        }
        command.commit()
    }

    private var viewportAspect: Float {
        let size = view.drawableSize
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return 1 }
        return Float(size.width / size.height)
    }

    private func updateTransforms(aspect: Float) {
        let safeAspect = aspect.isFinite && aspect > 0 ? max(0.01, min(aspect, 100)) : 1
        let halfVertical = configuration.verticalFieldOfView * .pi / 360
        let verticalTangent = tan(halfVertical)
        if isHumanAvatarScene, humanRegion != .whole {
            let horizontalHalf = atan(verticalTangent * min(safeAspect, 1))
            let target = humanRegion.target
            let transformed = modelTransform * SIMD4<Float>(target.x, target.y, target.z, 1)
            camera.target = SIMD3<Float>(transformed.x, transformed.y, transformed.z)
            let focusDistance = max(humanRegion.radius / sin(horizontalHalf) * 1.10,
                                    humanRegion.radius + configuration.nearClip * 2)
            camera.position = camera.target + SIMD3<Float>(0, 0, focusDistance)
            camera.farClip = max(configuration.farClip, focusDistance + 2)
            viewProjection = projection(verticalFOV: configuration.verticalFieldOfView, aspect: safeAspect,
                                        near: configuration.nearClip, far: camera.farClip) *
                lookAt(eye: camera.position, target: camera.target)
            return
        }
        let largestVerticalExtent = max(configuration.targetHeight, 1.8 - configuration.targetHeight)
        let radius = fittedSurfaceRadius ?? sqrt(largestVerticalExtent * largestVerticalExtent + 0.4 * 0.4)
        let distance: Float
        if let bounds = measurementBounds {
            // Eight transformed box corners bound every body/clothing vertex at
            // any permitted orbit; no per-frame mesh scan or copied position array.
            var halfWidth: Float = 0
            var halfHeight: Float = 0
            var depth: Float = 0
            for corner in 0..<8 {
                let point = SIMD4<Float>(
                    corner & 1 == 0 ? bounds.minimum.x : bounds.maximum.x,
                    corner & 2 == 0 ? bounds.minimum.y : bounds.maximum.y,
                    corner & 4 == 0 ? bounds.minimum.z : bounds.maximum.z, 1
                )
                let transformed = modelTransform * point
                halfWidth = max(halfWidth, abs(transformed.x))
                halfHeight = max(halfHeight, abs(transformed.y - configuration.targetHeight))
                depth = max(depth, abs(transformed.z))
            }
            distance = max(halfHeight / verticalTangent,
                           halfWidth / (verticalTangent * safeAspect)) * 1.10 + depth + configuration.nearClip
        } else if isHumanAvatarScene {
            let bounds = mannequin.mesh
            let halfWidth = max(abs(bounds.minimum.x), abs(bounds.maximum.x))
            let depth = max(abs(bounds.minimum.z), abs(bounds.maximum.z))
            distance = max(largestVerticalExtent / verticalTangent,
                           halfWidth / (verticalTangent * safeAspect)) * 1.10 + depth
        } else {
            let horizontalHalf = atan(verticalTangent * min(safeAspect, 1))
            let framedDistance = radius / sin(horizontalHalf) * (fittedSurfaceRadius == nil ? 1.02 : 1.08)
            distance = fittedSurfaceRadius == nil
                ? max(configuration.cameraDistance, framedDistance)
                : max(framedDistance, radius + configuration.nearClip * 2)
        }
        camera.target = SIMD3<Float>(0, configuration.targetHeight, 0)
        camera.position = SIMD3<Float>(0, configuration.targetHeight, distance)
        camera.farClip = max(configuration.farClip, distance + radius + 0.1)
        viewProjection = projection(verticalFOV: configuration.verticalFieldOfView, aspect: safeAspect,
                                    near: configuration.nearClip, far: camera.farClip) *
            lookAt(eye: camera.position, target: camera.target)
    }


    private func encode(object: RendererRenderObject, encoder: MTLRenderCommandEncoder) {
        guard let indexBuffer = object.indexBuffer else { return }
        var uniforms = VertexUniforms(modelViewProjection: viewProjection * modelTransform, model: modelTransform,
                                      hasClearance: object.clearanceBuffer == nil ? 0 : 1)
        let bounds = humanRegion.bounds
        var fragment = FragmentUniforms(
            color: object.color,
            regionMinimum: SIMD4<Float>(bounds.minimum.x, bounds.minimum.y, bounds.minimum.z,
                                         isHumanAvatarScene && humanRegion != .whole ? 1 : 0),
            regionMaximum: SIMD4<Float>(bounds.maximum.x, bounds.maximum.y, bounds.maximum.z,
                                         isHumanAvatarScene ? 1 : 0),
            mapEnabled: isHumanAvatarScene && humanMapVisible && object === garment && object.clearanceBuffer != nil ? 1 : 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<VertexUniforms>.stride, index: 1)
        encoder.setFragmentBytes(&fragment, length: MemoryLayout<FragmentUniforms>.stride, index: 0)
        encoder.setVertexBuffer(object.clearanceBuffer ?? object.vertexBuffer, offset: 0, index: 2)
        encoder.drawIndexedPrimitives(type: .triangle, indexCount: object.mesh.indices.count,
                                      indexType: .uint16, indexBuffer: indexBuffer, indexBufferOffset: 0)
    }

    private static func translation(_ value: SIMD3<Float>) -> simd_float4x4 {
        var result = matrix_identity_float4x4
        result.columns.3 = SIMD4<Float>(value, 1)
        return result
    }

    private func lookAt(eye: SIMD3<Float>, target: SIMD3<Float>) -> simd_float4x4 {
        let z = simd_normalize(eye - target)
        let x = simd_normalize(simd_cross(SIMD3<Float>(0, 1, 0), z))
        let y = simd_cross(z, x)
        return simd_float4x4(columns: (SIMD4<Float>(x.x, y.x, z.x, 0), SIMD4<Float>(x.y, y.y, z.y, 0),
                                       SIMD4<Float>(x.z, y.z, z.z, 0), SIMD4<Float>(-simd_dot(x, eye), -simd_dot(y, eye), -simd_dot(z, eye), 1)))
    }

    private func projection(verticalFOV: Float, aspect: Float, near: Float, far: Float) -> simd_float4x4 {
        let y = 1 / tan(verticalFOV * .pi / 360)
        let x = y / aspect
        let z = far / (near - far)
        return simd_float4x4(columns: (SIMD4<Float>(x, 0, 0, 0), SIMD4<Float>(0, y, 0, 0),
                                       SIMD4<Float>(0, 0, z, -1), SIMD4<Float>(0, 0, z * near, 0)))
    }

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;
    struct Vertex { float3 position; float3 normal; };
    struct VertexUniforms { float4x4 mvp; float4x4 model; uint hasClearance; };
    struct FragmentUniforms { float4 color; float4 regionMinimum; float4 regionMaximum; uint mapEnabled; };
    struct Out { float4 position [[position]]; float3 normal; float3 localPosition; float clearance; };
    vertex Out rendererVertex(uint id [[vertex_id]], const device Vertex *vertices [[buffer(0)]], constant VertexUniforms &u [[buffer(1)]], const device float *clearances [[buffer(2)]]) {
        Out o;
        o.position = u.mvp * float4(vertices[id].position, 1);
        o.normal = normalize((u.model * float4(vertices[id].normal, 0)).xyz);
        o.localPosition = vertices[id].position;
        o.clearance = u.hasClearance != 0 ? clearances[id] : -1.0;
        return o;
    }
    fragment float4 rendererFragment(Out in [[stage_in]], constant FragmentUniforms &u [[buffer(0)]]) {
        float3 n = normalize(in.normal); float3 light = normalize(float3(-0.35, 0.75, 0.65));
        float diffuse = max(dot(n, light), 0.0);
        float illumination = 0.30 + 0.70 * diffuse;
        float3 base = u.color.rgb;
        if (u.regionMaximum.w > 0.5) {
            float fill = max(dot(n, normalize(float3(0.7, 0.25, 0.5))), 0.0);
            illumination = 0.25 + 0.60 * diffuse + 0.18 * fill;
            if (u.mapEnabled != 0 && in.clearance >= 0.0) {
                float t = clamp((in.clearance - 0.004) / 0.026, 0.0, 1.0);
                float3 close = float3(0.94, 0.13, 0.10);
                float3 middle = float3(0.98, 0.63, 0.12);
                float3 roomy = float3(0.16, 0.70, 0.34);
                base = t < 0.45 ? mix(close, middle, t / 0.45) : mix(middle, roomy, (t - 0.45) / 0.55);
            }
            if (u.regionMinimum.w > 0.5 && all(in.localPosition >= u.regionMinimum.xyz) && all(in.localPosition <= u.regionMaximum.xyz)) {
                base = mix(base, float3(0.32, 0.66, 0.90), 0.12);
            }
            float specular = pow(max(dot(reflect(-light, n), float3(0, 0, 1)), 0.0), 36.0) * 0.07;
            return float4(base * illumination + specular, u.color.a);
        }
        return float4(base * illumination, u.color.a);
    }
    """
}
#endif
