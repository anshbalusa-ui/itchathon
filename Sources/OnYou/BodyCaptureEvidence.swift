import RealityKit
import Vision

actor BodyCaptureEvidence {
  struct Observation: Sendable {
    var meters: Double?
    var capturedAt: Date
    var torsoVisible: Bool
    var legsVisible: Bool
  }
  private var lastFile: URL?

  func latest(in directory: URL) async -> Observation? {
    do {
      let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
        .filter { ["heic", "heif"].contains($0.pathExtension.lowercased()) }
      let dated = files.compactMap { url -> (URL, Date)? in
        guard let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else { return nil }
        return (url, date)
      }
      guard let file = dated.max(by: { $0.1 < $1.1 })?.0,
            file != lastFile else { return nil }
      let sample = try await PhotogrammetrySample(contentsOf: file)
      try Task.checkCancellation()
      let request = VNDetectHumanBodyPoseRequest()
      try? VNImageRequestHandler(cvPixelBuffer: sample.image, orientation: sample.orientation).perform([request])
      try Task.checkCancellation()
      lastFile = file
      let points = (try? request.results?.first?.recognizedPoints(.all)) ?? [:]
      return Observation(
        meters: sample.objectMask == nil ? nil : CaptureDepthSampler.meters(sample.depthDataMap, confidence: sample.depthConfidenceMap, mask: sample.objectMask),
        capturedAt: sample.captureTime ?? (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast,
        torsoVisible: Self.visible([.leftShoulder, .rightShoulder, .leftHip, .rightHip], in: points),
        legsVisible: Self.visible([.leftHip, .rightHip, .leftKnee, .rightKnee, .leftAnkle, .rightAnkle], in: points))
    } catch { return nil }
  }

  nonisolated static func visible(_ names: [VNHumanBodyPoseObservation.JointName], in points: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]) -> Bool {
    !names.isEmpty && names.allSatisfy { name in
      guard let point = points[name], point.confidence >= 0.4 else { return false }
      return point.location.x.isFinite && point.location.y.isFinite && (0...1).contains(point.location.x) && (0...1).contains(point.location.y)
    }
  }
}
