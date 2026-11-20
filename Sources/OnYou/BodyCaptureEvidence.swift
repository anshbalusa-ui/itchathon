import CoreGraphics
import Vision

enum BodyCaptureEvidence {

  static func fullyVisible(_ points: [VNHumanBodyPoseObservation.JointName: CGPoint]) -> Bool {
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

  static func visible(_ names: [VNHumanBodyPoseObservation.JointName], in points: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]) -> Bool {
    !names.isEmpty && names.allSatisfy { name in
      guard let point = points[name], point.confidence >= 0.4 else { return false }
      return point.location.x.isFinite && point.location.y.isFinite && (0...1).contains(point.location.x) && (0...1).contains(point.location.y)
    }
  }
}
