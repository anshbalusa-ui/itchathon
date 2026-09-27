import Foundation

enum FitBand: String, Codable {
    case incompatible = "Too Small"
    case veryTight = "Very Tight"
    case fitted = "Fitted"
    case comfortable = "Ideal"
    case relaxed = "Relaxed"
    case tooLarge = "Too Large"
    case unknown = "Unknown"
}

struct FitDimensionResult: Identifiable, Equatable {
    let id = UUID()
    let label: String
    let bodyMeters: Double
    let garmentMeters: Double
    let easeMeters: Double

    /// Signed fit score on a -100...100 scale.
    /// -100 = much too small, 0 = ideal target ease, +100 = much too large.
    let score: Int

    let band: FitBand
}

struct FitReport: Equatable {
    /// Signed aggregate fit score on a -100...100 scale.
    /// The closer this is to zero, the closer the garment is to the target fit.
    let score: Int
    let band: FitBand
    let dimensions: [FitDimensionResult]

    var distanceFromIdeal: Int { abs(score) }
}

/// A single labeled clothing size evaluated against one saved body profile.
struct SizeFitResult: Identifiable, Equatable {
    var id: String { sizeLabel }

    let sizeLabel: String
    let report: FitReport
    let summary: String
}

/// Keeps retailer/garment size order for display while exposing the size whose
/// aggregate signed score is closest to zero.
struct SizeComparisonReport: Equatable {
    let sizes: [SizeFitResult]

    var closestMatch: SizeFitResult? {
        sizes.min { lhs, rhs in
            let lhsDistance = abs(lhs.report.score)
            let rhsDistance = abs(rhs.report.score)

            if lhsDistance == rhsDistance {
                let lhsWorst = lhs.report.dimensions.map { abs($0.score) }.max() ?? 100
                let rhsWorst = rhs.report.dimensions.map { abs($0.score) }.max() ?? 100
                return lhsWorst < rhsWorst
            }

            return lhsDistance < rhsDistance
        }
    }
}

enum FitEngine {
    private struct EaseTarget {
        let ideal: ClosedRange<Double>
        let acceptable: ClosedRange<Double>

        var center: Double {
            (ideal.lowerBound + ideal.upperBound) / 2
        }
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

        let signedScore = clamp(
            Int((weighted / max(totalWeight, 0.001)).rounded())
        )

        return FitReport(
            score: signedScore,
            band: overallBand(score: signedScore, dimensions: results),
            dimensions: results
        )
    }

    /// Evaluate every real size in a garment's size chart against the same user.
    ///
    /// Size measurements must come from the retailer/seller or be measured.
    /// We intentionally do not generate neighboring sizes by adding a constant
    /// increment because apparel grading differs by brand and product.
    static func evaluateSizes(
        body: BodyProfile,
        chart: GarmentSizeChart
    ) -> SizeComparisonReport {
        let results = chart.sizes.map { size -> SizeFitResult in
            let garment = size.asGarment(
                named: chart.garmentName,
                category: chart.category
            )

            let report = evaluate(body: body, garment: garment)

            return SizeFitResult(
                sizeLabel: size.label,
                report: report,
                summary: sizeSummary(report)
            )
        }

        return SizeComparisonReport(sizes: results)
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

    /// Maps garment ease to a signed scale centered on the desired ease.
    ///
    /// The target's ideal midpoint is 0.
    /// Its acceptable lower bound maps to -100.
    /// Its acceptable upper bound maps to +100.
    /// Values beyond those bounds remain clamped at -100 / +100.
    private static func evaluateDimension(
        label: String,
        body: Double,
        garment: Double,
        target: EaseTarget
    ) -> FitDimensionResult {
        let ease = garment - body
        let center = target.center

        let rawScore: Double
        if ease < center {
            let smallRange = max(center - target.acceptable.lowerBound, 0.001)
            rawScore = -100 * ((center - ease) / smallRange)
        } else if ease > center {
            let largeRange = max(target.acceptable.upperBound - center, 0.001)
            rawScore = 100 * ((ease - center) / largeRange)
        } else {
            rawScore = 0
        }

        let score = clamp(Int(rawScore.rounded()))
        let band = band(for: score)

        return FitDimensionResult(
            label: label,
            bodyMeters: body,
            garmentMeters: garment,
            easeMeters: ease,
            score: score,
            band: band
        )
    }

    private static func overallBand(
        score: Int,
        dimensions: [FitDimensionResult]
    ) -> FitBand {
        guard !dimensions.isEmpty else { return .unknown }

        // A severe local mismatch should remain visible even if another
        // dimension pulls the weighted average back toward zero.
        if dimensions.contains(where: { $0.score <= -80 }) {
            return .incompatible
        }

        if dimensions.contains(where: { $0.score >= 80 }) {
            return .tooLarge
        }

        return band(for: score)
    }

    private static func band(for score: Int) -> FitBand {
        switch score {
        case ...(-70):
            return .incompatible
        case -69...(-30):
            return .veryTight
        case -29...(-10):
            return .fitted
        case -9...9:
            return .comfortable
        case 10...69:
            return .relaxed
        case 70...:
            return .tooLarge
        default:
            return .unknown
        }
    }

    private static func clamp(_ score: Int) -> Int {
        min(100, max(-100, score))
    }

    private static func sizeSummary(_ report: FitReport) -> String {
        guard !report.dimensions.isEmpty else {
            return "Not enough measurements to describe this size."
        }

        let phrases = report.dimensions.map { result -> String in
            let area: String
            switch result.label {
            case "Chest": area = "through the chest"
            case "Waist": area = "through the waist"
            case "Shoulders": area = "at the shoulders"
            default: area = "at the \(result.label.lowercased())"
            }

            switch result.band {
            case .incompatible:
                return "too small \(area)"
            case .veryTight:
                return "very snug \(area)"
            case .fitted:
                return "fitted \(area)"
            case .comfortable:
                return "near ideal \(area)"
            case .relaxed:
                return "relaxed \(area)"
            case .tooLarge:
                return "too large \(area)"
            case .unknown:
                return "unknown \(area)"
            }
        }

        if phrases.count == 1 {
            return phrases[0].capitalized + "."
        }

        let joined = phrases.dropLast().joined(separator: ", ")
            + ", and "
            + (phrases.last ?? "")

        return joined.prefix(1).uppercased() + String(joined.dropFirst()) + "."
    }
}
