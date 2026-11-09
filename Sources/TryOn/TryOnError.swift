import Foundation

enum TryOnError: LocalizedError {
  case body, shirt, pose, surface, geometry, missingDimensions, missingPhoto
  var errorDescription: String? {
    switch self {
    case .body: "Your body scan couldn’t be opened. Your saved scan has been kept."
    case .shirt: "We couldn’t read the shirt’s shape clearly. Retake its scan with the sleeves spread and collar at the top."
    case .pose: "This scan doesn’t show a supported standing pose clearly enough. Retake with feet fully visible and arms slightly away from the torso. Your saved scan is unchanged."
    case .surface: "The scan doesn’t provide a continuous surface for this shirt preview. Try another saved shirt, or retake the body scan with clear views of the shoulders, torso and arms. Your saved scan is unchanged."
    case .geometry: "The shirt preview couldn’t be built. Your scans are unchanged. Try again."
    case .missingDimensions: "This is a photo-only garment. Scan the actual shirt to establish its scale before opening a 3D preview."
    case .missingPhoto: "The saved shirt image is missing or unreadable. Retake the shirt scan from its garment page. Your other items are unchanged."
    }
  }
}
