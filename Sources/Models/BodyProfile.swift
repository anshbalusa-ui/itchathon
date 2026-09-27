import Foundation

struct BodyProfile: Codable, Equatable {
    var chestCircumference: Double = 0
    var waistCircumference: Double = 0
    var hipCircumference: Double = 0
    var shoulderWidth: Double = 0
    var torsoLength: Double = 0
    var updatedAt: Date = .now

    var isUsable: Bool {
        chestCircumference > 0 && shoulderWidth > 0
    }

    static let demo = BodyProfile(
        chestCircumference: 1.08,
        waistCircumference: 0.98,
        hipCircumference: 1.10,
        shoulderWidth: 0.48,
        torsoLength: 0.68
    )
}
