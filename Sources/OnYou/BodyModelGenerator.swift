import Foundation

struct BodyModelGeometry: Sendable {
  let body: RendererMesh
  let shorts: RendererMesh
}

actor BodyModelGenerator {
  static let shared = BodyModelGenerator()

  private struct Prepared: Sendable {
    let assets: HumanShowcaseMeshes
    let kernel: BodyShapeKernel
  }

  private var prepared: Prepared?

  func generate(_ measurements: BodyMeasurements) throws -> BodyModelGeometry {
    try Task.checkCancellation()
    guard measurements.isValid else { throw CocoaError(.validationMissingMandatoryProperty) }
    if prepared == nil {
      let assets = try HumanShowcaseAssets.load()
      prepared = Prepared(assets: assets, kernel: try BodyShapeKernel(reference: assets.body))
    }
    guard let prepared else { throw HumanShowcaseAssetFailure.rejectedPayload }
    try Task.checkCancellation()
    let body = try prepared.kernel.shape(prepared.assets.body, to: measurements)
    try Task.checkCancellation()
    let shorts = try prepared.kernel.shape(prepared.assets.shorts, to: measurements)
    return BodyModelGeometry(body: body, shorts: shorts)
  }
}
