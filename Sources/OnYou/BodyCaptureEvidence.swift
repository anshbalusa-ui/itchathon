import RealityKit
import Vision

actor BodyCaptureEvidence {
  struct Observation: Sendable {
    var meters: Double?
    var capturedAt: Date
    var torsoVisible: Bool
    var legsVisible: Bool
    var fullBodyVisible: Bool
  }
  private var inspected = Set<URL>()

  func latest(in directory: URL) async -> Observation? {
    do {
      let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
        .filter { ["heic", "heif"].contains($0.pathExtension.lowercased()) && !inspected.contains($0) }
      let dated = files.compactMap { url -> (URL, Date)? in
        guard let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else { return nil }
        return (url, date)
      }
      guard let file = dated.max(by: { $0.1 < $1.1 })?.0 else { return nil }
      let sample = try await PhotogrammetrySample(contentsOf: file)
      try Task.checkCancellation()
      let request = VNDetectHumanBodyPoseRequest()
      try? VNImageRequestHandler(cvPixelBuffer: sample.image, orientation: sample.orientation).perform([request])
      try Task.checkCancellation()
      inspected.insert(file)
      let points = (try? request.results?.first?.recognizedPoints(.all)) ?? [:]
      return Observation(
        meters: sample.objectMask == nil ? nil : CaptureDepthSampler.meters(sample.depthDataMap, confidence: sample.depthConfidenceMap, mask: sample.objectMask),
        capturedAt: sample.captureTime ?? (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast,
        torsoVisible: Self.visible([.leftShoulder, .rightShoulder, .leftHip, .rightHip], in: points),
        legsVisible: Self.visible([.leftHip, .rightHip, .leftKnee, .rightKnee, .leftAnkle, .rightAnkle], in: points),
        fullBodyVisible: request.results?.count == 1 && Self.fullyVisible(points.filter { $0.value.confidence >= 0.4 }.mapValues(\.location)))
    } catch { return nil }
  }

  nonisolated static func fullyVisible(_ points: [VNHumanBodyPoseObservation.JointName: CGPoint]) -> Bool {
    let body: [VNHumanBodyPoseObservation.JointName] = [.leftShoulder, .rightShoulder, .leftHip, .rightHip, .leftAnkle, .rightAnkle]
    guard body.allSatisfy({ name in
      guard let p = points[name] else { return false }
      return p.x.isFinite && p.y.isFinite && (0.02...0.98).contains(p.x) && (0.02...0.98).contains(p.y)
    }), let head = [points[.nose], points[.leftEar], points[.rightEar]].compactMap({ $0 }).first(where: {
      $0.x.isFinite && $0.y.isFinite && (0.02...0.98).contains($0.x) && (0.02...0.98).contains($0.y)
    }) else { return false }
    // Vision points use an upright image with a lower-left origin.
    let shoulders = (points[.leftShoulder]!.y + points[.rightShoulder]!.y) / 2
    let hips = (points[.leftHip]!.y + points[.rightHip]!.y) / 2
    return head.y > shoulders && shoulders > hips && hips > max(points[.leftAnkle]!.y, points[.rightAnkle]!.y)
  }

  nonisolated static func visible(_ names: [VNHumanBodyPoseObservation.JointName], in points: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]) -> Bool {
    !names.isEmpty && names.allSatisfy { name in
      guard let point = points[name], point.confidence >= 0.4 else { return false }
      return point.location.x.isFinite && point.location.y.isFinite && (0...1).contains(point.location.x) && (0...1).contains(point.location.y)
    }
  }
}
