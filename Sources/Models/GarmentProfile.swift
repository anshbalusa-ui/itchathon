import Foundation

enum GarmentCategory: String, Codable, CaseIterable, Identifiable {
    case tshirt
    case hoodie
    case jacket
    case shirt

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tshirt: return "T-Shirt"
        case .hoodie: return "Hoodie"
        case .jacket: return "Jacket"
        case .shirt: return "Shirt"
        }
    }
}

struct GarmentProfile: Codable, Equatable {
    var name: String = "Scanned garment"
    var category: GarmentCategory = .tshirt

    /// Width measured with the garment laid flat.
    var chestFlat: Double = 0
    var waistFlat: Double = 0
    var shoulderWidth: Double = 0
    var length: Double = 0

    var chestCircumferenceApprox: Double { chestFlat * 2 }
    var waistCircumferenceApprox: Double { waistFlat * 2 }

    var isUsable: Bool {
        chestFlat > 0 && shoulderWidth > 0
    }

    static let demo = GarmentProfile(
        name: "Demo tee",
        category: .tshirt,
        chestFlat: 0.59,
        waistFlat: 0.57,
        shoulderWidth: 0.50,
        length: 0.72
    )
}
