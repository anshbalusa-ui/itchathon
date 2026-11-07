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

  var scale: Float { Float(referenceHeightCM / 100) / capturedHeightM }
  var heightM: Float { Float(referenceHeightCM / 100) }
  var scaleCorrection: Double { Double(abs(scale - 1) * 100) }
  var isValid: Bool {
    BodyMeasurementField.height.range.contains(referenceHeightCM)
      && [capturedHeightM, widthM, depthM].allSatisfy { $0.isFinite && $0 > 0 }
      && (0.9...1.1).contains(scale) && widthM * scale < 2 && depthM * scale < 1.2
      && imageCount >= 60 && completedPasses >= 2
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

  var size: SIMD3<Float> { maximum - minimum }
  var scale: Float { Float(referenceHeightCM / 100) / size.y }

  func validate() throws {
    guard BodyMeasurementField.height.range.contains(referenceHeightCM),
          (0..<3).allSatisfy({ minimum[$0].isFinite && maximum[$0].isFinite && size[$0] > 0 }),
          (0.9...1.1).contains(scale), size.x * scale < 2, size.z * scale < 1.2 else {
      throw AvatarScanError.invalidScale
    }
  }
}

enum AvatarScanError: LocalizedError {
  case invalidScale, invalidModel, insufficientCoverage, unsupported, unavailableCamera, insufficientSpace

  var errorDescription: String? {
    switch self {
    case .invalidScale: "The captured height differs from your reference by more than 10%, or the model includes too much of the room. Retake with the selection box fitted closely from head to feet."
    case .invalidModel: "The reconstructed model is missing, damaged, or has no photo texture. Retake the scan. Your existing avatar is unchanged."
    case .insufficientCoverage: "Complete two full passes and capture at least 60 images before building your avatar."
    case .unsupported: "3D capture needs a supported iPhone with LiDAR. This device can still view avatars and use manual measurements."
    case .unavailableCamera: "Camera access is off. Enable it in Settings to start a scan."
    case .insufficientSpace: "Free at least 2 GB of storage before starting a scan."
    }
  }
}
