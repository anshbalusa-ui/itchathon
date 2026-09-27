import Foundation

enum FitDimension: String, Codable, CaseIterable, Identifiable {
    case chest
    case shoulders
    case length

    var id: String { rawValue }
}

enum PhysicalStatus: String, Codable {
    case passesMeasuredChecks
    case needsVerification
    case smallerThanBody
}

struct PhysicalCheck: Identifiable, Equatable {
    let id: String
    let bodyMeters: Double
    let candidateMeters: Double
    let easeMeters: Double
    let status: PhysicalStatus
}

struct FitDimensionResult: Identifiable, Equatable {
    let id: FitDimension
    let preferredMeters: Double
    let candidateMeters: Double
    let deltaMeters: Double
    let signedScore: Int
    let normalizedDelta: Double
}

struct FitReport: Equatable {
    let physical: PhysicalStatus
    let referencePhysical: PhysicalStatus
    let checks: [PhysicalCheck]
    let dimensions: [FitDimensionResult]
    let preferredName: String
    let waistAssessed: Bool
    let isMixed: Bool
}

enum FitInputError: Error, Equatable, LocalizedError {
    case incompleteBody
    case incompleteGarment
    case unsupportedCategory
    case contradictoryReference
    case invalidChart

    var errorDescription: String? {
        switch self {
        case .incompleteBody:
            return "Body measurements must be finite and positive for chest, waist, shoulders, and torso."
        case .incompleteGarment:
            return "Garment chest, shoulders, and length must be finite and positive; optional waist cannot be negative."
        case .unsupportedCategory:
            return "Fit comparison currently supports T-shirts only."
        case .contradictoryReference:
            return "The preferred garment chest is smaller than the measured body chest; verify both measurements before comparison."
        case .invalidChart:
            return "The size chart must contain a name and finished T-shirt garment measurements."
        }
    }
}

struct SizeFitResult: Identifiable, Equatable {
    let id: UUID
    let sizeLabel: String
    let report: FitReport?
    let issue: String?
}

struct SizeComparisonReport: Equatable {
    let sizes: [SizeFitResult]
    let recommendedIDs: [UUID]
}

enum FitEngine {
    private struct ScoringConfiguration {
        func scale(for dimension: FitDimension) -> Double {
            switch dimension {
            case .chest: return 0.12
            case .shoulders: return 0.06
            case .length: return 0.12
            }
        }

        func deadband(for dimension: FitDimension) -> Double {
            switch dimension {
            case .chest: return 0.01
            case .shoulders: return 0.005
            case .length: return 0.005
            }
        }

        let reviewMarginMeters = 0.03
        let tieTolerance = 0.02
    }

    private static let configuration = ScoringConfiguration()


    static func evaluate(
        body: BodyProfile,
        preferred: GarmentProfile,
        garment: GarmentProfile
    ) throws -> FitReport {
        guard body.isUsable else { throw FitInputError.incompleteBody }
        try validate(garment: preferred)
        try validate(garment: garment)
        guard preferred.category == .tshirt, garment.category == .tshirt else {
            throw FitInputError.unsupportedCategory
        }

        guard let preferredChest = doubledWidth(preferred.chestFlat),
              let candidateChest = doubledWidth(garment.chestFlat),
              preferredChest >= body.chestCircumference else {
            throw FitInputError.contradictoryReference
        }

        let referenceWaist = try waistObservation(body: body, garment: preferred)
        let candidateWaist = try waistObservation(body: body, garment: garment)
        let referenceChecks = [try physicalCheck(
            id: MeasurementKey.chestCircumference.rawValue,
            body: body.chestCircumference,
            garment: preferredChest,
            bodyOrigin: body.origins?[MeasurementKey.chestCircumference.rawValue],
            garmentOrigin: preferred.origins?[MeasurementKey.garmentChestFlat.rawValue]
        )] + (referenceWaist.map { [$0] } ?? [])
        let checks = [try physicalCheck(
            id: MeasurementKey.chestCircumference.rawValue,
            body: body.chestCircumference,
            garment: candidateChest,
            bodyOrigin: body.origins?[MeasurementKey.chestCircumference.rawValue],
            garmentOrigin: garment.origins?[MeasurementKey.garmentChestFlat.rawValue]
        )] + (candidateWaist.map { [$0] } ?? [])

        let dimensions = try FitDimension.allCases.map { dimension in
            try dimensionResult(
                dimension,
                preferred: dimensionValue(dimension, in: preferred),
                candidate: dimensionValue(dimension, in: garment)
            )
        }
        let physical = combinedStatus(checks.map(\.status))
        let referencePhysical = combinedStatus(referenceChecks.map(\.status))
        let signs = dimensions.compactMap { result -> Int? in
            abs(result.deltaMeters) <= configuration.deadband(for: result.id)
                ? nil
                : (result.deltaMeters < 0 ? -1 : 1)
        }

        return FitReport(
            physical: physical,
            referencePhysical: referencePhysical,
            checks: checks,
            dimensions: dimensions,
            preferredName: preferred.name,
            waistAssessed: candidateWaist != nil,
            isMixed: signs.contains(-1) && signs.contains(1)
        )
    }

    static func evaluateSizes(
        body: BodyProfile,
        preferred: GarmentProfile,
        chart: GarmentSizeChart
    ) throws -> SizeComparisonReport {
        guard !chart.garmentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              chart.category == .tshirt,
              chart.measurementBasis == .finishedGarment,
              !chart.sizes.isEmpty else {
            throw FitInputError.invalidChart
        }
        guard body.isUsable else { throw FitInputError.incompleteBody }
        try validate(garment: preferred)
        guard preferred.category == .tshirt else { throw FitInputError.unsupportedCategory }
        guard let referenceChest = doubledWidth(preferred.chestFlat),
              referenceChest >= body.chestCircumference else {
            throw FitInputError.contradictoryReference
        }

        let sizes = try chart.sizes.map { size -> SizeFitResult in
            let id = size.id
            guard !size.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return SizeFitResult(
                    id: id,
                    sizeLabel: size.label,
                    report: nil,
                    issue: FitInputError.incompleteGarment.localizedDescription
                )
            }
            let garment = size.asGarment(named: chart.garmentName, category: chart.category)
            do {
                return SizeFitResult(
                    id: id,
                    sizeLabel: size.label,
                    report: try evaluate(body: body, preferred: preferred, garment: garment),
                    issue: nil
                )
            } catch let error as FitInputError {
                return SizeFitResult(
                    id: id,
                    sizeLabel: size.label,
                    report: nil,
                    issue: error.localizedDescription
                )
            }
        }

        let eligible = sizes.compactMap { row -> (UUID, Double)? in
            guard let report = row.report,
                  report.physical == .passesMeasuredChecks,
                  report.referencePhysical == .passesMeasuredChecks else { return nil }
            return (row.id, report.dimensions.map { abs($0.normalizedDelta) }.max() ?? .infinity)
        }
        guard let best = eligible.map({ $0.1 }).min() else {
            return SizeComparisonReport(sizes: sizes, recommendedIDs: [])
        }
        let recommended = eligible.compactMap { distance in
            distance.1 - best <= configuration.tieTolerance ? distance.0 : nil
        }
        return SizeComparisonReport(sizes: sizes, recommendedIDs: recommended)
    }

    private static func validate(garment: GarmentProfile) throws {
        guard garment.isUsable else { throw FitInputError.incompleteGarment }
    }

    private static func doubledWidth(_ width: Double) -> Double? {
        let doubled = width * 2
        return doubled.isFinite && doubled > 0 ? doubled : nil
    }

    private static func waistObservation(
        body: BodyProfile,
        garment: GarmentProfile
    ) throws -> PhysicalCheck? {
        guard garment.waistAtNavel == true else { return nil }
        guard garment.waistFlat == 0 || doubledWidth(garment.waistFlat) != nil else {
            throw FitInputError.incompleteGarment
        }
        guard garment.waistFlat > 0,
              let circumference = doubledWidth(garment.waistFlat) else { return nil }
        return try physicalCheck(
            id: MeasurementKey.waistCircumference.rawValue,
            body: body.waistCircumference,
            garment: circumference,
            bodyOrigin: body.origins?[MeasurementKey.waistCircumference.rawValue],
            garmentOrigin: garment.origins?[MeasurementKey.garmentWaistFlat.rawValue]
        )
    }

    private static func physicalCheck(
        id: String,
        body: Double,
        garment: Double,
        bodyOrigin: MeasurementOrigin?,
        garmentOrigin: MeasurementOrigin?
    ) throws -> PhysicalCheck {
        let ease = garment - body
        guard ease.isFinite else { throw FitInputError.incompleteGarment }

        let status: PhysicalStatus
        if ease < 0 {
            status = .smallerThanBody
        } else if requiresVerification(bodyOrigin, garmentOrigin) {
            status = .needsVerification
        } else {
            let bodyError = verifiedError(bodyOrigin) ?? 0
            let flatError = verifiedError(garmentOrigin) ?? 0
            let margin = max(configuration.reviewMarginMeters, bodyError + 2 * flatError)
            guard margin.isFinite else { throw FitInputError.incompleteGarment }
            let boundaryTolerance = 8 * max(ease.ulp, margin.ulp)
            status = ease <= margin + boundaryTolerance ? .needsVerification : .passesMeasuredChecks
        }
        return PhysicalCheck(id: id, bodyMeters: body, candidateMeters: garment, easeMeters: ease, status: status)
    }

    private static func requiresVerification(_ body: MeasurementOrigin?, _ garment: MeasurementOrigin?) -> Bool {
        requiresVerification(body) || requiresVerification(garment)
    }

    private static func requiresVerification(_ origin: MeasurementOrigin?) -> Bool {
        guard let origin else { return false }
        return (origin.source == .bodyScan || origin.source == .garmentScan)
            && !origin.verifiedWithTape
            && verifiedError(origin) == nil
    }

    private static func verifiedError(_ origin: MeasurementOrigin?) -> Double? {
        guard let origin, !origin.verifiedWithTape,
              let error = origin.observedErrorMeters, error.isFinite, error >= 0 else { return nil }
        return error
    }

    private static func combinedStatus(_ statuses: [PhysicalStatus]) -> PhysicalStatus {
        if statuses.contains(.smallerThanBody) { return .smallerThanBody }
        if statuses.contains(.needsVerification) { return .needsVerification }
        return .passesMeasuredChecks
    }

    private static func dimensionValue(_ dimension: FitDimension, in garment: GarmentProfile) -> Double {
        switch dimension {
        case .chest: return garment.chestCircumferenceApprox
        case .shoulders: return garment.shoulderWidth
        case .length: return garment.length
        }
    }

    private static func dimensionResult(
        _ dimension: FitDimension,
        preferred: Double,
        candidate: Double
    ) throws -> FitDimensionResult {
        let delta = candidate - preferred
        let normalized = delta / configuration.scale(for: dimension)
        guard delta.isFinite, normalized.isFinite else { throw FitInputError.incompleteGarment }
        let bounded = min(100.0, max(-100.0, normalized * 100))
        guard bounded.isFinite else { throw FitInputError.incompleteGarment }
        return FitDimensionResult(
            id: dimension,
            preferredMeters: preferred,
            candidateMeters: candidate,
            deltaMeters: delta,
            signedScore: Int(bounded.rounded()),
            normalizedDelta: normalized
        )
    }
}
