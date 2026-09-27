import XCTest
@testable import FitCheck

final class FitEngineTests: XCTestCase {
    private let body = BodyProfile(
        chestCircumference: 1.0,
        waistCircumference: 0.9,
        hipCircumference: 0,
        shoulderWidth: 0.46,
        torsoLength: 0.45
    )

    private let favorite = GarmentProfile(
        name: "Favorite",
        category: .tshirt,
        chestFlat: 0.60,
        waistFlat: 0,
        shoulderWidth: 0.50,
        length: 0.72
    )

    private func garment(
        chestFlat: Double = 0.60,
        waistFlat: Double = 0,
        shoulderWidth: Double = 0.50,
        length: Double = 0.72,
        waistAtNavel: Bool? = nil,
        origins: [String: MeasurementOrigin]? = nil,
        name: String = "Candidate"
    ) -> GarmentProfile {
        GarmentProfile(
            name: name,
            category: .tshirt,
            chestFlat: chestFlat,
            waistFlat: waistFlat,
            shoulderWidth: shoulderWidth,
            length: length,
            waistAtNavel: waistAtNavel,
            origins: origins
        )
    }

    private func chart(_ sizes: [GarmentSizeVariant],
                       basis: ChartMeasurementBasis? = .finishedGarment) -> GarmentSizeChart {
        GarmentSizeChart(
            garmentName: "Synthetic tee",
            brand: nil,
            category: .tshirt,
            sizes: sizes,
            measurementBasis: basis,
            sourceNote: "Synthetic test data"
        )
    }

    private func row(
        _ label: String,
        id: UUID = UUID(),
        chestFlat: Double = 0.60,
        waistFlat: Double = 0,
        shoulderWidth: Double = 0.50,
        length: Double = 0.72,
        waistAtNavel: Bool? = nil
    ) -> GarmentSizeVariant {
        GarmentSizeVariant(
            id: id,
            label: label,
            chestFlat: chestFlat,
            waistFlat: waistFlat,
            shoulderWidth: shoulderWidth,
            length: length,
            waistAtNavel: waistAtNavel
        )
    }

    func testExactMatchAndSymmetricSignedScores() throws {
        let exact = try FitEngine.evaluate(body: body, preferred: favorite, garment: favorite)
        XCTAssertEqual(exact.dimensions.map(\.id), [.chest, .shoulders, .length])
        XCTAssertEqual(exact.dimensions.map(\.signedScore), [0, 0, 0])

        let larger = try FitEngine.evaluate(
            body: body, preferred: favorite,
            garment: garment(chestFlat: 0.63, shoulderWidth: 0.53, length: 0.78)
        )
        let smaller = try FitEngine.evaluate(
            body: body, preferred: favorite,
            garment: garment(chestFlat: 0.57, shoulderWidth: 0.47, length: 0.66)
        )
        XCTAssertEqual(larger.dimensions.map(\.signedScore), [50, 50, 50])
        XCTAssertEqual(smaller.dimensions.map(\.signedScore), [-50, -50, -50])
        for index in 0..<3 {
            XCTAssertEqual(larger.dimensions[index].normalizedDelta, 0.5, accuracy: 1e-12)
            XCTAssertEqual(smaller.dimensions[index].normalizedDelta, -0.5, accuracy: 1e-12)
        }
    }

    func testScoresSaturateButNormalizedRankRemainsUnbounded() throws {
        let atEndpoint = try FitEngine.evaluate(
            body: body, preferred: favorite,
            garment: garment(chestFlat: 0.66, shoulderWidth: 0.56, length: 0.84)
        )
        XCTAssertEqual(atEndpoint.dimensions.map(\.signedScore), [100, 100, 100])
        for index in 0..<3 {
            XCTAssertEqual(atEndpoint.dimensions[index].normalizedDelta, 1, accuracy: 1e-12)
        }

        let beyondEndpoint = try FitEngine.evaluate(
            body: body, preferred: favorite,
            garment: garment(chestFlat: 0.72, shoulderWidth: 0.62, length: 0.96)
        )
        XCTAssertEqual(beyondEndpoint.dimensions.map(\.signedScore), [100, 100, 100])
        for index in 0..<3 {
            XCTAssertEqual(beyondEndpoint.dimensions[index].normalizedDelta, 2, accuracy: 1e-12)
        }
    }

    func testOppositeDimensionErrorsRemainSeparate() throws {
        let report = try FitEngine.evaluate(
            body: body,
            preferred: favorite,
            garment: garment(chestFlat: 0.57, length: 0.78)
        )
        XCTAssertEqual(report.dimensions.map(\.signedScore), [-50, 0, 50])
        XCTAssertTrue(report.isMixed)
        XCTAssertEqual(report.physical, .passesMeasuredChecks)
        XCTAssertFalse(report.waistAssessed)
    }

    func testPhysicalChestConstraintIsIndependentOfShoulderAndLengthPreference() throws {
        let tooSmall = try FitEngine.evaluate(
            body: body,
            preferred: favorite,
            garment: garment(chestFlat: 0.49, shoulderWidth: 0.50, length: 0.72)
        )
        XCTAssertEqual(tooSmall.dimensions.map(\.signedScore), [-100, 0, 0])
        XCTAssertEqual(tooSmall.physical, .smallerThanBody)
    }

    func testPhysicalChecksCompareBodyCircumferenceWithTwiceFlatGarmentWidth() throws {
        let report = try FitEngine.evaluate(
            body: body, preferred: favorite,
            garment: garment(chestFlat: 0.55, waistFlat: 0.46, waistAtNavel: true)
        )
        let chest = try XCTUnwrap(report.checks.first { $0.id == MeasurementKey.chestCircumference.rawValue })
        let waist = try XCTUnwrap(report.checks.first { $0.id == MeasurementKey.waistCircumference.rawValue })
        XCTAssertEqual(chest.candidateMeters, 1.10, accuracy: 1e-12)
        XCTAssertEqual(chest.easeMeters, 0.10, accuracy: 1e-12)
        XCTAssertEqual(waist.candidateMeters, 0.92, accuracy: 1e-12)
        XCTAssertEqual(waist.easeMeters, 0.02, accuracy: 1e-12)
        XCTAssertEqual(waist.status, .needsVerification)
    }

    func testContradictoryFavoriteThrowsInsteadOfRedefiningTheReference() {
        let tooSmallFavorite = garment(chestFlat: 0.49, name: "Contradictory favorite")
        XCTAssertThrowsError(
            try FitEngine.evaluate(body: body, preferred: tooSmallFavorite, garment: favorite)
        ) { error in
            guard case FitInputError.contradictoryReference = error else {
                return XCTFail("Expected contradictoryReference, got \(error)")
            }
        }
    }

    func testClosePhysicalBoundaryRequiresReview() throws {
        let report = try FitEngine.evaluate(
            body: body, preferred: favorite,
            garment: garment(chestFlat: 0.5149)
        )
        XCTAssertEqual(report.physical, .needsVerification)
    }

    func testUnverifiedBodyScanRequiresVerification() throws {
        let scannedBody = BodyProfile(
            chestCircumference: body.chestCircumference,
            waistCircumference: body.waistCircumference,
            hipCircumference: body.hipCircumference,
            shoulderWidth: body.shoulderWidth,
            torsoLength: body.torsoLength,
            origins: [
                MeasurementKey.chestCircumference.rawValue:
                    MeasurementOrigin(source: .bodyScan)
            ]
        )
        let report = try FitEngine.evaluate(body: scannedBody, preferred: favorite, garment: favorite)
        XCTAssertEqual(report.physical, .needsVerification)
    }

    func testTapeVerificationAndObservedScanErrorsAffectReviewMargin() throws {
        let verifiedBody = BodyProfile(
            chestCircumference: body.chestCircumference,
            waistCircumference: body.waistCircumference,
            hipCircumference: body.hipCircumference,
            shoulderWidth: body.shoulderWidth,
            torsoLength: body.torsoLength,
            origins: [
                MeasurementKey.chestCircumference.rawValue:
                    MeasurementOrigin(source: .bodyScan, verifiedWithTape: true)
            ]
        )
        let uncertainBody = BodyProfile(
            chestCircumference: body.chestCircumference,
            waistCircumference: body.waistCircumference,
            hipCircumference: body.hipCircumference,
            shoulderWidth: body.shoulderWidth,
            torsoLength: body.torsoLength,
            origins: [
                MeasurementKey.chestCircumference.rawValue:
                    MeasurementOrigin(source: .bodyScan, observedErrorMeters: 0.02)
            ]
        )
        let garmentOrigin = [
            MeasurementKey.garmentChestFlat.rawValue:
                MeasurementOrigin(source: .garmentScan, observedErrorMeters: 0.01)
        ]
        let candidate = garment(chestFlat: 0.52, origins: garmentOrigin)

        let verified = try FitEngine.evaluate(body: verifiedBody, preferred: favorite, garment: candidate)
        let uncertain = try FitEngine.evaluate(body: uncertainBody, preferred: favorite, garment: candidate)
        XCTAssertEqual(verified.physical, .passesMeasuredChecks)
        XCTAssertEqual(uncertain.physical, .needsVerification)
    }

    func testWaistIsAssessedOnlyWhenGarmentLevelIsAligned() throws {
        let aligned = try FitEngine.evaluate(
            body: body, preferred: favorite,
            garment: garment(waistFlat: 0.46, waistAtNavel: true)
        )
        let unaligned = try FitEngine.evaluate(
            body: body, preferred: favorite,
            garment: garment(waistFlat: 0.46, waistAtNavel: false)
        )
        XCTAssertTrue(aligned.waistAssessed)
        XCTAssertEqual(aligned.checks.count, 2)
        XCTAssertFalse(unaligned.waistAssessed)
        XCTAssertEqual(unaligned.checks.count, 1)
    }

    func testInvalidWaistAndDerivedOverflowAreRejected() {
        var invalidWaist = favorite
        invalidWaist.waistFlat = -0.01
        XCTAssertFalse(invalidWaist.isUsable)
        XCTAssertThrowsError(
            try FitEngine.evaluate(body: body, preferred: invalidWaist, garment: favorite)
        )

        var overflowingGarment = favorite
        overflowingGarment.chestFlat = .greatestFiniteMagnitude
        XCTAssertFalse(overflowingGarment.isUsable)
        XCTAssertThrowsError(
            try FitEngine.evaluate(body: body, preferred: favorite, garment: overflowingGarment)
        )
    }

    func testFiniteInputsWithOverflowingNormalizedDifferenceAreRejected() {
        let hugeFavorite = garment(chestFlat: .greatestFiniteMagnitude / 4)
        XCTAssertTrue(hugeFavorite.isUsable)
        XCTAssertThrowsError(
            try FitEngine.evaluate(body: body, preferred: hugeFavorite, garment: favorite)
        )
    }

    func testSizeChartRejectsNonFinishedGarmentBasis() {
        for basis in [ChartMeasurementBasis.bodyRecommendation, nil] {
            XCTAssertThrowsError(
                try FitEngine.evaluateSizes(body: body, preferred: favorite, chart: chart([row("M")], basis: basis))
            ) { error in
                guard case FitInputError.invalidChart = error else {
                    return XCTFail("Expected invalidChart, got \(error)")
                }
            }
        }
    }

    func testSizeRowsKeepIncompleteAndPhysicallyIncompatibleEntriesVisibleButIneligible() throws {
        let incomplete = row("Incomplete", chestFlat: 0)
        let tooSmall = row("Too small", chestFlat: 0.49, shoulderWidth: 0.50, length: 0.72)
        let comparison = try FitEngine.evaluateSizes(
            body: body, preferred: favorite, chart: chart([incomplete, tooSmall])
        )
        XCTAssertEqual(comparison.sizes.count, 2)
        XCTAssertNil(comparison.sizes[0].report)
        XCTAssertNotNil(comparison.sizes[0].issue)
        XCTAssertEqual(comparison.sizes[1].report?.physical, .smallerThanBody)
        XCTAssertTrue(comparison.recommendedIDs.isEmpty)
    }

    func testMinimaxDoesNotLetOppositeErrorsCancel() throws {
        let cancelling = row("Cancelling", chestFlat: 0.54, shoulderWidth: 0.56, length: 0.72)
        let balanced = row("Balanced", chestFlat: 0.612, shoulderWidth: 0.512, length: 0.744)
        let comparison = try FitEngine.evaluateSizes(
            body: body, preferred: favorite, chart: chart([cancelling, balanced])
        )
        XCTAssertEqual(comparison.sizes[0].report?.dimensions.map(\.signedScore), [-100, 100, 0])
        XCTAssertEqual(comparison.sizes[1].report?.dimensions.map(\.signedScore), [20, 20, 20])
        XCTAssertEqual(comparison.recommendedIDs, [balanced.id])
    }

    func testNearMinimaxTiesIncludeDuplicateLabelsAndPreserveUUIDIdentity() throws {
        let firstID = UUID()
        let secondID = UUID()
        let first = row("M", id: firstID, chestFlat: 0.612, shoulderWidth: 0.50, length: 0.72)
        let second = row("M", id: secondID, chestFlat: 0.6131, shoulderWidth: 0.50, length: 0.72)
        let comparison = try FitEngine.evaluateSizes(
            body: body, preferred: favorite, chart: chart([first, second])
        )
        XCTAssertEqual(comparison.sizes.map(\.id), [firstID, secondID])
        XCTAssertEqual(Set(comparison.recommendedIDs), Set([firstID, secondID]))
    }

    func testAllIncompatibleRowsHaveNoRecommendationAndLabelsDoNotAffectScores() throws {
        let small = row("XXL", chestFlat: 0.49)
        let duplicate = row("XS", chestFlat: 0.49)
        let comparison = try FitEngine.evaluateSizes(
            body: body, preferred: favorite, chart: chart([small, duplicate])
        )
        XCTAssertTrue(comparison.recommendedIDs.isEmpty)
        XCTAssertEqual(comparison.sizes[0].report?.dimensions.map(\.signedScore),
                       comparison.sizes[1].report?.dimensions.map(\.signedScore))
    }
    func testCentimetersAndInchesConvertToEquivalentMeters() {
        let centimeterValue = LengthUnit.centimeters.meters(116.84)
        let inchValue = LengthUnit.inches.meters(46)
        XCTAssertEqual(centimeterValue, 1.1684, accuracy: 1e-12)
        XCTAssertEqual(inchValue, centimeterValue, accuracy: 1e-12)
        XCTAssertEqual(LengthUnit.centimeters.display(centimeterValue), 116.84, accuracy: 1e-10)
        XCTAssertEqual(LengthUnit.inches.display(inchValue), 46, accuracy: 1e-10)
    }
    func testLegacyGarmentJSONDecodesWithoutManufacturedMetadata() throws {
        let json = Data(#"{"name":"Legacy tee","category":"tshirt","chestFlat":0.6,"waistFlat":0.0,"shoulderWidth":0.5,"length":0.72}"#.utf8)
        let decoded = try JSONDecoder().decode(GarmentProfile.self, from: json)
        XCTAssertEqual(decoded.name, "Legacy tee")
        XCTAssertEqual(decoded.chestFlat, 0.6)
        XCTAssertNil(decoded.origins)
        XCTAssertNil(decoded.waistAtNavel)
    }


    func testLegacyBodyJSONDecodesWithoutManufacturedOrigins() throws {
        let json = Data(#"{"chestCircumference":1.0,"waistCircumference":0.9,"hipCircumference":0.0,"shoulderWidth":0.46,"torsoLength":0.45,"updatedAt":0}"#.utf8)
        let decoded = try JSONDecoder().decode(BodyProfile.self, from: json)
        XCTAssertEqual(decoded.chestCircumference, 1.0)
        XCTAssertEqual(decoded.waistCircumference, 0.9)
        XCTAssertEqual(decoded.hipCircumference, 0.0)
        XCTAssertEqual(decoded.shoulderWidth, 0.46)
        XCTAssertEqual(decoded.torsoLength, 0.45)
        XCTAssertNil(decoded.origins)
    }

}
