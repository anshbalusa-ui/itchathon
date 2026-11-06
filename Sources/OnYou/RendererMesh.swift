import simd

struct RendererVertex: Sendable {
    var position: SIMD3<Float>
    var normal: SIMD3<Float>
}

struct RendererMesh: Sendable {
    let vertices: [RendererVertex]
    let indices: [UInt16]
    var minimum: SIMD3<Float>
    var maximum: SIMD3<Float>
    /// Authored shell-to-body offsets for the human showcase only; never personal fit data.
    var sampleClearance: [Float]? = nil
}

