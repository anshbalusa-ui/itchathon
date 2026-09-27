import Foundation

enum FitBand: String, Codable {
    case incompatible = "Won't Fit"
    case veryTight = "Very Tight"
    case fitted = "Fitted"
    case comfortable = "Comfortable"
    case relaxed = "Relaxed"
    case unknown = "Unknown"
}

struct FitDimensionResult: Identifiable, Equatable {
    let id = UUID()
    let label: String
    let bodyMeters: Double
    let garmentMeters: Double
    let easeMeters: Double
    let score: Int
    let band: FitBand
}

struct FitReport: Equatable {
    let score: Int
    let band: FitBand
    let dimensions: [FitDimensionResult]
}

enum FitEngine {
    private struct EaseTarget {
        let ideal: ClosedRange<Double>
        let acceptable: ClosedRange<Double>
    }

    static func evaluate(body: BodyProfile, garment: GarmentProfile) -> FitReport {
        var results: [FitDimensionResult] = []

        if body.chestCircumference > 0, garment.chestFlat > 0 {
            results.append(
                evaluateDimension(
                    label: "Chest",
                    body: body.chestCircumference,
                    garment: garment.chestCircumferenceApprox,
                    target: chestTarget(for: garment.category)
                )
            )
        }

        if body.waistCircumference > 0, garment.waistFlat > 0 {
            results.append(
                evaluateDimension(
                    label: "Waist",
                    body: body.waistCircumference,
                    garment: garment.waistCircumferenceApprox,
                    target: EaseTarget(ideal: 0.06...0.18, acceptable: 0.00...0.28)
                )
            )
        }

        if body.shoulderWidth > 0, garment.shoulderWidth > 0 {
            results.append(
                evaluateDimension(
                    label: "Shoulders",
                    body: body.shoulderWidth,
                    garment: garment.shoulderWidth,
                    target: EaseTarget(ideal: 0.00...0.035, acceptable: -0.015...0.065)
                )
            )
        }

        guard !results.isEmpty else {
            return FitReport(score: 0, band: .unknown, dimensions: [])
        }

        let weights: [String: Double] = [
            "Chest": 0.50,
            "Waist": 0.25,
            "Shoulders": 0.25
        ]

        var weighted = 0.0
        var totalWeight = 0.0
        for result in results {
            let weight = weights[result.label] ?? 1
            weighted += Double(result.score) * weight
            totalWeight += weight
        }

        let score = Int((weighted / max(totalWeight, 0.001)).rounded())
        return FitReport(
            score: score,
            band: overallBand(score: score, dimensions: results),
            dimensions: results
        )
    }

    private static func chestTarget(for category: GarmentCategory) -> EaseTarget {
        switch category {
        case .tshirt:
            return EaseTarget(ideal: 0.05...0.14, acceptable: 0.00...0.24)
        case .shirt:
            return EaseTarget(ideal: 0.06...0.16, acceptable: 0.00...0.25)
        case .hoodie:
            return EaseTarget(ideal: 0.10...0.24, acceptable: 0.03...0.34)
        case .jacket:
            return EaseTarget(ideal: 0.10...0.26, acceptable: 0.03...0.36)
        }
    }

    private static func evaluateDimension(
        label: String,
        body: Double,
        garment: Double,
        target: EaseTarget
    ) -> FitDimensionResult {
        let ease = garment - body
        let score: Int
        let band: FitBand

        if ease < target.acceptable.lowerBound {
            let miss = target.acceptable.lowerBound - ease
            score = max(0, 45 - Int(miss * 500))
            band = ease < 0 ? .incompatible : .veryTight
        } else if target.ideal.contains(ease) {
            score = 100
            band = .comfortable
        } else if ease < target.ideal.lowerBound {
            let distance = target.ideal.lowerBound - ease
            score = max(55, 100 - Int(distance * 450))
            band = .fitted
        } else if ease <= target.acceptable.upperBound {
            let distance = ease - target.ideal.upperBound
            score = max(65, 100 - Int(distance * 300))
            band = .relaxed
        } else {
            let excess = ease - target.acceptable.upperBound
            score = max(35, 70 - Int(excess * 250))
            band = .relaxed
        }

        return FitDimensionResult(
            label: label,
            bodyMeters: body,
            garmentMeters: garment,
            easeMeters: ease,
            score: min(100, score),
            band: band
        )
    }

    private static func overallBand(
        score: Int,
        dimensions: [FitDimensionResult]
    ) -> FitBand {
        if dimensions.contains(where: { $0.band == .incompatible }) { return .incompatible }
        if score >= 90 { return .comfortable }
        if score >= 75 { return .fitted }
        if score >= 60 { return .veryTight }
        return .incompatible
    }
}
