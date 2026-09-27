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

/// A single labeled clothing size evaluated against one saved body profile.
struct SizeFitResult: Identifiable, Equatable {
    var id: String { sizeLabel }

    let sizeLabel: String
    let report: FitReport
    let summary: String
}

/// Keeps the retailer/garment size order for display while separately exposing
/// the highest measurement-based match.
struct SizeComparisonReport: Equatable {
    let sizes: [SizeFitResult]

    var closestMatch: SizeFitResult? {
        sizes.max { lhs, rhs in
            lhs.report.score < rhs.report.score
        }
    }
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

    /// Evaluate every real size in a garment's size chart against the same user.
    ///
    /// Size measurements must come from the retailer/seller or be measured.
    /// We intentionally do not generate fake neighboring sizes by adding a
    /// constant increment because apparel grading differs by brand and product.
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

    private static func evaluateDimension(
        label: String,
        body: Double,
        garment: Double,
        target: EaseTarget
    ) -> FitDimensionResult {
        let ease = garment - body
        let score: Int
        let band: FitBand

        if target.ideal.contains(ease) {
            // Scores peak at the center of the intended ease range rather than
            // giving every acceptable "ideal" measurement an identical 100.
            let center = (target.ideal.lowerBound + target.ideal.upperBound) / 2
            let halfWidth = max((target.ideal.upperBound - target.ideal.lowerBound) / 2, 0.001)
            let normalizedDistance = min(abs(ease - center) / halfWidth, 1)
            score = Int((100 - (normalizedDistance * 10)).rounded())

            let span = max(target.ideal.upperBound - target.ideal.lowerBound, 0.001)
            let position = (ease - target.ideal.lowerBound) / span
            if position < 0.33 {
                band = .fitted
            } else if position > 0.67 {
                band = .relaxed
            } else {
                band = .comfortable
            }
        } else if ease >= target.acceptable.lowerBound,
                  ease < target.ideal.lowerBound {
            let gap = max(target.ideal.lowerBound - target.acceptable.lowerBound, 0.001)
            let normalizedDistance = (target.ideal.lowerBound - ease) / gap
            score = max(55, Int((90 - normalizedDistance * 30).rounded()))
            band = .veryTight
        } else if ease > target.ideal.upperBound,
                  ease <= target.acceptable.upperBound {
            let gap = max(target.acceptable.upperBound - target.ideal.upperBound, 0.001)
            let normalizedDistance = (ease - target.ideal.upperBound) / gap
            score = max(55, Int((90 - normalizedDistance * 30).rounded()))
            band = .relaxed
        } else if ease < target.acceptable.lowerBound {
            let miss = target.acceptable.lowerBound - ease
            score = max(0, 45 - Int(miss * 500))
            band = .incompatible
        } else {
            let excess = ease - target.acceptable.upperBound
            score = max(35, 55 - Int(excess * 250))
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
        guard !dimensions.isEmpty else { return .unknown }
        if dimensions.contains(where: { $0.band == .incompatible }) { return .incompatible }
        if dimensions.contains(where: { $0.band == .veryTight }) { return .veryTight }

        let relaxedCount = dimensions.filter { $0.band == .relaxed }.count
        let fittedCount = dimensions.filter { $0.band == .fitted }.count

        if relaxedCount >= 2 { return .relaxed }
        if fittedCount >= 2 { return .fitted }
        if score >= 90 { return .comfortable }
        return .fitted
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
                return "comfortable \(area)"
            case .relaxed:
                return "relaxed \(area)"
            case .unknown:
                return "unknown \(area)"
            }
        }

        if phrases.count == 1 {
            return phrases[0].capitalized + "."
        }

        let last = phrases.last ?? ""
        let leading = phrases.dropLast().joined(separator: ", ")
        return (leading + ", and " + last).prefix(1).uppercased()
            + String((leading + ", and " + last).dropFirst()) + "."
    }
}
