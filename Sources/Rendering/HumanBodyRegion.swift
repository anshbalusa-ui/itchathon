#if DEBUG
import Foundation
import simd

/// Authored locations on the neutral 1.80 m demonstration model, not measured landmarks.
enum HumanBodyRegion: String, CaseIterable, Identifiable, Sendable {
    case whole, head, shoulders, chest, waist, hips, arms, legs

    var id: String { rawValue }
    var title: String {
        switch self {
        case .whole: "Whole body"
        case .head: "Head"
        case .shoulders: "Shoulders"
        case .chest: "Chest"
        case .waist: "Waist"
        case .hips: "Hips"
        case .arms: "Arms"
        case .legs: "Legs"
        }
    }

    var target: SIMD3<Float> {
        switch self {
        case .whole: SIMD3(0, 0.9, 0)
        case .head: SIMD3(0, 1.67, 0.01)
        case .shoulders: SIMD3(0, 1.43, 0)
        case .chest: SIMD3(0, 1.30, 0.03)
        case .waist: SIMD3(0, 1.08, 0.02)
        case .hips: SIMD3(0, 0.91, 0)
        case .arms: SIMD3(0, 1.21, 0)
        case .legs: SIMD3(0, 0.47, 0)
        }
    }

    var radius: Float {
        switch self {
        case .whole: 1.05
        case .head: 0.17
        case .shoulders: 0.34
        case .chest: 0.25
        case .waist: 0.23
        case .hips: 0.26
        case .arms: 0.57
        case .legs: 0.48
        }
    }

    var bounds: (minimum: SIMD3<Float>, maximum: SIMD3<Float>) {
        switch self {
        case .whole: (SIMD3(-1, 0, -1), SIMD3(1, 1.81, 1))
        case .head: (SIMD3(-0.16, 1.53, -0.18), SIMD3(0.16, 1.81, 0.20))
        case .shoulders: (SIMD3(-0.34, 1.36, -0.22), SIMD3(0.34, 1.53, 0.22))
        case .chest: (SIMD3(-0.25, 1.18, -0.23), SIMD3(0.25, 1.39, 0.25))
        case .waist: (SIMD3(-0.24, 1.00, -0.23), SIMD3(0.24, 1.18, 0.25))
        case .hips: (SIMD3(-0.28, 0.79, -0.25), SIMD3(0.28, 1.01, 0.25))
        case .arms: (SIMD3(-0.66, 0.96, -0.25), SIMD3(0.66, 1.45, 0.25))
        case .legs: (SIMD3(-0.27, 0.03, -0.25), SIMD3(0.27, 0.88, 0.30))
        }
    }
}

enum HumanShowcaseGarment: Equatable, Sendable {
    case shirt, vest
    var assetIdentifier: String {
        switch self {
        case .shirt: "fitcheck.human-showcase.shirt.v1"
        case .vest: "fitcheck.human-showcase.vest.v1"
        }
    }
}
#endif
