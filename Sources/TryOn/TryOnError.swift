import Foundation

enum TryOnError: LocalizedError {
  case body, shirt, pose, surface, geometry
  var errorDescription: String? {
    switch self {
    case .body: "Your body scan couldn’t be opened. Your saved scan has been kept."
    case .shirt: "We couldn’t read the shirt’s shape clearly. Retake its scan with the sleeves spread and collar at the top."
    case .pose: "We couldn’t locate the shoulders and arms in this scan. Try a body scan with your arms slightly away from your sides."
    case .surface: "The torso has gaps that prevent this preview. Retake the body scan with the whole person visible throughout each circle."
    case .geometry: "The shirt preview couldn’t be built. Your scans are unchanged. Try again."
    }
  }
}
