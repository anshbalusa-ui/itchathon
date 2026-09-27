import Foundation
import Combine

@MainActor
final class ProfileStore: ObservableObject {
    @Published var bodyProfile: BodyProfile
    @Published var currentGarment: GarmentProfile
    @Published var currentSizeChart: GarmentSizeChart?
    @Published var lastReport: FitReport?
    @Published var sizeComparison: SizeComparisonReport?

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
        currentSizeChart = nil
    }

    func saveBodyProfile() {
        bodyProfile.updatedAt = .now
        guard let data = try? JSONEncoder().encode(bodyProfile) else { return }
        UserDefaults.standard.set(data, forKey: bodyKey)
    }

    func evaluateCurrentGarment() {
        lastReport = FitEngine.evaluate(body: bodyProfile, garment: currentGarment)
    }

    func evaluateAvailableSizes() {
        guard let currentSizeChart else {
            sizeComparison = nil
            return
        }

        sizeComparison = FitEngine.evaluateSizes(
            body: bodyProfile,
            chart: currentSizeChart
        )
    }

    func loadDemoData() {
        bodyProfile = .demo
        currentGarment = .demo
        currentSizeChart = .demo
        evaluateCurrentGarment()
        evaluateAvailableSizes()
    }
}
