import Foundation

@MainActor
final class ProfileStore: ObservableObject {
    @Published var bodyProfile: BodyProfile
    @Published var currentGarment: GarmentProfile
    @Published var lastReport: FitReport?

    private let bodyKey = "fitcheck.bodyProfile"

    init() {
        if
            let data = UserDefaults.standard.data(forKey: bodyKey),
            let decoded = try? JSONDecoder().decode(BodyProfile.self, from: data)
        {
            bodyProfile = decoded
        } else {
            bodyProfile = BodyProfile()
        }

        currentGarment = GarmentProfile()
    }

    func saveBodyProfile() {
        bodyProfile.updatedAt = .now
        guard let data = try? JSONEncoder().encode(bodyProfile) else { return }
        UserDefaults.standard.set(data, forKey: bodyKey)
    }

    func evaluateCurrentGarment() {
        lastReport = FitEngine.evaluate(body: bodyProfile, garment: currentGarment)
    }

    func loadDemoData() {
        bodyProfile = .demo
        currentGarment = .demo
        evaluateCurrentGarment()
    }
}
