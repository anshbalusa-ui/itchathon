import Foundation
import simd

struct AvatarScanRecord: Codable, Identifiable, Equatable {
  var id: UUID
  var date: Date
  var referenceHeightCM: Double
  var capturedHeightM: Float
  var widthM: Float
  var depthM: Float
  var imageCount: Int
  var completedPasses: Int
  var sha256: String
  var usesDepthScale: Bool? = nil

  var scale: Float { Float(referenceHeightCM / 100) / capturedHeightM }
  var heightM: Float { Float(referenceHeightCM / 100) }
  var scaleCorrection: Double { Double(abs(scale - 1) * 100) }
  var isValid: Bool {
    BodyMeasurementField.height.range.contains(referenceHeightCM)
      && [capturedHeightM, widthM, depthM].allSatisfy { $0.isFinite && $0 > 0 }
      && (usesDepthScale != true || abs(scale - 1) < 0.0001)
      && (0.9...1.1).contains(scale) && widthM * scale < 2 && depthM * scale < 1.2
      && AvatarScanInput.hasCoverage(images: imageCount, passes: completedPasses)
      && sha256.count == 64 && sha256.allSatisfy { $0.isHexDigit && !$0.isUppercase }
  }
}

struct AvatarScanAsset: Equatable {
  var record: AvatarScanRecord
  var url: URL
}

struct AvatarScanCalibration: Equatable {
  var minimum: SIMD3<Float>
  var maximum: SIMD3<Float>
  var referenceHeightCM: Double
  var usesDepthScale = false

  var size: SIMD3<Float> { maximum - minimum }
  var scale: Float { Float(referenceHeightCM / 100) / size.y }

  func validate() throws {
    guard BodyMeasurementField.height.range.contains(referenceHeightCM),
          (0..<3).allSatisfy({ minimum[$0].isFinite && maximum[$0].isFinite && size[$0] > 0 }),
          (!usesDepthScale || abs(scale - 1) < 0.0001),
          (0.9...1.1).contains(scale), size.x * scale < 2, size.z * scale < 1.2 else {
      throw AvatarScanError.invalidScale
    }
  }
}

enum AvatarScanError: LocalizedError {
  case invalidScale, invalidModel, insufficientCoverage, unsupported, unavailableCamera, insufficientSpace, missingDepth

  var errorDescription: String? {
    switch self {
    case .invalidScale: "The scan’s scale or bounds look wrong. Retake with the selection box fitted closely from head to feet."
    case .invalidModel: "The reconstructed model is missing, damaged, or has no photo texture. Retake the scan. Your existing avatar is unchanged."
    case .insufficientCoverage: "Complete the body and detail passes before building your avatar."
    case .unsupported: "Body capture needs a supported iPhone with LiDAR. This device can still view saved avatars and your closet."
    case .unavailableCamera: "Camera access is off. Enable it in Settings to start a scan."
    case .missingDepth: "The photos don’t contain enough depth to establish real-world scale. Retake on a supported LiDAR iPhone."
    case .insufficientSpace: "Make more storage available on your iPhone before starting a scan."
    }
  }
}
