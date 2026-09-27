import XCTest
@testable import FitCheck

final class SizeChartTests: XCTestCase {
    func testLegacyRowsGenerateDistinctStableIDsAndRetainMeasurements() throws {
        let legacyRow = #"{"label":"M","chestFlat":0.6,"waistFlat":0.5,"shoulderWidth":0.45,"length":0.7}"#.data(using: .utf8)!
        let decoder = JSONDecoder()
        let first = try decoder.decode(GarmentSizeVariant.self, from: legacyRow)
        let second = try decoder.decode(GarmentSizeVariant.self, from: legacyRow)

        XCTAssertEqual(first.label, "M")
        XCTAssertEqual(first.chestFlat, 0.6)
        XCTAssertEqual(first.waistFlat, 0.5)
        XCTAssertEqual(first.shoulderWidth, 0.45)
        XCTAssertEqual(first.length, 0.7)
        XCTAssertNotEqual(first.id, second.id)

        let encoded = try JSONEncoder().encode(first)
        let roundTripped = try decoder.decode(GarmentSizeVariant.self, from: encoded)
        XCTAssertEqual(roundTripped.id, first.id)
        XCTAssertEqual(roundTripped, first)

        let duplicateLabels = [first, second]
        XCTAssertEqual(duplicateLabels.map(\.label), ["M", "M"])
        XCTAssertEqual(Set(duplicateLabels.map(\.id)).count, 2)
    }

    func testChestInputBasisAndGarmentCircumferenceUseMetersConsistently() {
        XCTAssertEqual(ChestInputBasis.circumference.flatMeters(from: 1.2), 0.6, accuracy: 1e-12)
        XCTAssertEqual(ChestInputBasis.flatWidth.flatMeters(from: 0.6), 0.6, accuracy: 1e-12)

        let garment = GarmentProfile(
            name: "Synthetic tee",
            category: .tshirt,
            chestFlat: ChestInputBasis.circumference.flatMeters(from: 1.2),
            waistFlat: 0,
            shoulderWidth: 0.45,
            length: 0.7
        )
        XCTAssertEqual(garment.chestFlat, 0.6, accuracy: 1e-12)
        XCTAssertEqual(garment.chestCircumferenceApprox, 1.2, accuracy: 1e-12)
    }

    func testChartRowIdentityProvenanceAndWaistAlignmentReachSizeEvaluation() throws {
        let body = BodyProfile(
            chestCircumference: 1.0,
            waistCircumference: 0.9,
            hipCircumference: 0,
            shoulderWidth: 0.46,
            torsoLength: 0.45
        )
        let preferred = GarmentProfile(
            name: "Favorite",
            category: .tshirt,
            chestFlat: 0.6,
            waistFlat: 0,
            shoulderWidth: 0.5,
            length: 0.72
        )
        let id = UUID()
        let scanOrigin = MeasurementOrigin(source: .garmentScan)
        let scannedRow = GarmentSizeVariant(
            id: id,
            label: "M",
            chestFlat: 0.8,
            waistFlat: 0.6,
            shoulderWidth: 0.5,
            length: 0.72,
            origins: [MeasurementKey.garmentChestFlat.rawValue: scanOrigin],
            waistAtNavel: true
        )
        let scannedGarment = scannedRow.asGarment(named: "Synthetic tee", category: .tshirt)

        XCTAssertEqual(scannedGarment.origins?[MeasurementKey.garmentChestFlat.rawValue], scanOrigin)
        XCTAssertEqual(scannedGarment.waistAtNavel, true)
        let scanEvaluation = try FitEngine.evaluateSizes(
            body: body,
            preferred: preferred,
            chart: GarmentSizeChart(garmentName: "Synthetic tee", brand: nil, category: .tshirt, sizes: [scannedRow], measurementBasis: .finishedGarment)
        )
        XCTAssertEqual(scanEvaluation.sizes.map(\.id), [id])
        XCTAssertEqual(scanEvaluation.sizes.first?.report?.checks.map(\.id), [MeasurementKey.chestCircumference.rawValue, MeasurementKey.waistCircumference.rawValue])
        let scanReport = try XCTUnwrap(scanEvaluation.sizes.first?.report)
        let waistCheck = try XCTUnwrap(scanReport.checks.last, "Expected the waist circumference check")
        XCTAssertEqual(waistCheck.candidateMeters, 1.2, accuracy: 1e-12)
        XCTAssertEqual(scanEvaluation.sizes.first?.report?.checks.last?.status, .passesMeasuredChecks)
        XCTAssertEqual(scanEvaluation.sizes.first?.report?.physical, .needsVerification)
        XCTAssertTrue(scanEvaluation.recommendedIDs.isEmpty)

        let verifiedRow = GarmentSizeVariant(
            id: id,
            label: "M",
            chestFlat: 0.8,
            waistFlat: 0.6,
            shoulderWidth: 0.5,
            length: 0.72,
            origins: [MeasurementKey.garmentChestFlat.rawValue: MeasurementOrigin(source: .garmentScan, verifiedWithTape: true)],
            waistAtNavel: true
        )
        let verifiedGarment = verifiedRow.asGarment(named: "Synthetic tee", category: .tshirt)
        XCTAssertEqual(verifiedGarment.origins?[MeasurementKey.garmentChestFlat.rawValue]?.verifiedWithTape, true)
        XCTAssertEqual(verifiedGarment.waistAtNavel, true)
        let verifiedEvaluation = try FitEngine.evaluateSizes(
            body: body,
            preferred: preferred,
            chart: GarmentSizeChart(garmentName: "Synthetic tee", brand: nil, category: .tshirt, sizes: [verifiedRow], measurementBasis: .finishedGarment)
        )
        XCTAssertEqual(verifiedEvaluation.sizes.map(\.id), [id])
        XCTAssertEqual(verifiedEvaluation.sizes.first?.report?.physical, .passesMeasuredChecks)
        XCTAssertEqual(verifiedEvaluation.recommendedIDs, [id])
    }
}
