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

    init(mesh: RendererMesh, color: SIMD4<Float>, device: MTLDevice) throws {
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
    }

    func update(color: SIMD4<Float>, isEnabled: Bool) {
        self.color = color
        self.isEnabled = isEnabled
    }

    func releaseBuffers() {
        vertexBuffer = nil
        indexBuffer = nil
    }
}

@MainActor
final class RendererSceneSession: NSObject, MTKViewDelegate {
    private struct VertexUniforms {
        var modelViewProjection: simd_float4x4
        var model: simd_float4x4
    }

    private struct FragmentUniforms {
        var color: SIMD4<Float>
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
    private var cachedGarment: RendererRenderObject?
    private let configuration: RendererSceneConfiguration
    private var orbit = RendererOrbit.initial
    private var appearance = RendererAppearance()
    private var isProceduralGarmentCached = false

    convenience init(configuration: RendererSceneConfiguration = .standard,
                      mannequinAsset: RendererAssetDescriptor = .mannequinFixture,
                      garmentAsset: RendererAssetDescriptor? = .garmentFixture) throws {
        try self.init(configuration: configuration, mannequinAsset: mannequinAsset, garmentAsset: garmentAsset,
                      generatedMesh: nil)
    }

    convenience init(geometry: GeometryResult) throws {
        let mesh = try GeometryRendererAdapter.mesh(from: geometry)
        try self.init(configuration: .standard, mannequinAsset: .mannequinFixture, garmentAsset: nil,
                      generatedMesh: mesh)
    }

    private init(configuration: RendererSceneConfiguration, mannequinAsset: RendererAssetDescriptor,
                 garmentAsset: RendererAssetDescriptor?, generatedMesh: RendererMesh?) throws {
        try configuration.validate()
        if generatedMesh == nil { try mannequinAsset.validate(for: .mannequin) }
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
        self.camera = RendererCamera(position: SIMD3<Float>(0, configuration.targetHeight, configuration.cameraDistance),
                                     target: SIMD3<Float>(0, configuration.targetHeight, 0),
                                     nearClip: configuration.nearClip, farClip: configuration.farClip,
                                     verticalFieldOfView: configuration.verticalFieldOfView)
        mannequin = try RendererRenderObject(mesh: generatedMesh ?? RendererProceduralAssets.mannequin(),
                                            color: generatedMesh == nil
                                                ? SIMD4<Float>(0.68, 0.65, 0.60, 1)
                                                : SIMD4<Float>(0.34, 0.49, 0.39, 1),
                                            device: device)
        if generatedMesh == nil, let garmentAsset {
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
        mannequin.update(color: isSyntheticGeometryScene
                         ? SIMD4<Float>(0.34, 0.49, 0.39, 1)
                         : SIMD4<Float>(0.68, 0.65, 0.60, 1), isEnabled: true)
        garment?.update(color: RendererProceduralAssets.color(for: appearance.material), isEnabled: appearance.garmentVisible)
        updateTransforms(aspect: viewportAspect)
        view.setNeedsDisplay()
    }
    func replaceGarment(asset: RendererAssetDescriptor?) throws {

        guard !isDisposed else { throw RendererFailure.sceneCreationFailed }
        guard !isSyntheticGeometryScene else { throw RendererFailure.unsupportedAsset }
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
        guard !isSyntheticGeometryScene else { throw RendererFailure.unsupportedAsset }
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
        let largestVerticalExtent = max(configuration.targetHeight, 1.8 - configuration.targetHeight)
        let radius = sqrt(largestVerticalExtent * largestVerticalExtent + 0.4 * 0.4)
        let horizontalHalf = atan(tan(halfVertical) * min(safeAspect, 1))
        let distance = max(configuration.cameraDistance, radius / sin(horizontalHalf) * 1.02)
        camera.position = SIMD3<Float>(0, configuration.targetHeight, distance)
        camera.farClip = max(configuration.farClip, distance + radius + 0.1)
        viewProjection = projection(verticalFOV: configuration.verticalFieldOfView, aspect: safeAspect,
                                    near: configuration.nearClip, far: camera.farClip) *
            lookAt(eye: camera.position, target: camera.target)
    }


    private func encode(object: RendererRenderObject, encoder: MTLRenderCommandEncoder) {
        guard let indexBuffer = object.indexBuffer else { return }
        var uniforms = VertexUniforms(modelViewProjection: viewProjection * modelTransform, model: modelTransform)
        var fragment = FragmentUniforms(color: object.color)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<VertexUniforms>.stride, index: 1)
        encoder.setFragmentBytes(&fragment, length: MemoryLayout<FragmentUniforms>.stride, index: 0)
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
    struct VertexUniforms { float4x4 mvp; float4x4 model; };
    struct FragmentUniforms { float4 color; };
    struct Out { float4 position [[position]]; float3 normal; };
    vertex Out rendererVertex(uint id [[vertex_id]], const device Vertex *vertices [[buffer(0)]], constant VertexUniforms &u [[buffer(1)]]) {
        Out o; o.position = u.mvp * float4(vertices[id].position, 1); o.normal = normalize((u.model * float4(vertices[id].normal, 0)).xyz); return o;
    }
    fragment float4 rendererFragment(Out in [[stage_in]], constant FragmentUniforms &u [[buffer(0)]]) {
        float3 n = normalize(in.normal); float3 light = normalize(float3(-0.35, 0.75, 0.65));
        float diffuse = max(dot(n, light), 0.0); float illumination = 0.30 + 0.70 * diffuse;
        return float4(u.color.rgb * illumination, u.color.a);
    }
    """
}
#endif
