import XCTest
@testable import FitCheck

final class FitEngineTests: XCTestCase {
    func testDemoGarmentProducesSignedReport() {
        let report = FitEngine.evaluate(body: .demo, garment: .demo)

        XCTAssertFalse(report.dimensions.isEmpty)
        XCTAssertGreaterThanOrEqual(report.score, -100)
        XCTAssertLessThanOrEqual(report.score, 100)
    }

    func testTooSmallGarmentProducesNegativeScore() {
        let body = BodyProfile(
            chestCircumference: 1.20,
            waistCircumference: 1.00,
            hipCircumference: 1.10,
            shoulderWidth: 0.50,
            torsoLength: 0.70
        )

        let garment = GarmentProfile(
            name: "Small tee",
            category: .tshirt,
            chestFlat: 0.50,
            waistFlat: 0.50,
            shoulderWidth: 0.47,
            length: 0.68
        )

        let report = FitEngine.evaluate(body: body, garment: garment)

        XCTAssertLessThan(report.score, 0)
        XCTAssertEqual(report.band, .incompatible)
    }

    func testOversizedGarmentProducesPositiveScore() {
        let garment = GarmentProfile(
            name: "Oversized tee",
            category: .tshirt,
            chestFlat: 0.76,
            waistFlat: 0.72,
            shoulderWidth: 0.62,
            length: 0.82
        )

        let report = FitEngine.evaluate(body: .demo, garment: garment)

        XCTAssertGreaterThan(report.score, 0)
        XCTAssertEqual(report.band, .tooLarge)
    }

    func testSizeChartScoresEveryAvailableSizeOnSignedScale() {
        let comparison = FitEngine.evaluateSizes(
            body: .demo,
            chart: .demo
        )

        XCTAssertEqual(comparison.sizes.count, GarmentSizeChart.demo.sizes.count)
        XCTAssertEqual(comparison.closestMatch?.sizeLabel, "2XL")

        for size in comparison.sizes {
            XCTAssertGreaterThanOrEqual(size.report.score, -100)
            XCTAssertLessThanOrEqual(size.report.score, 100)
            XCTAssertFalse(size.summary.isEmpty)
        }
    }

    func testClosestMatchMeansClosestToZero() {
        let comparison = FitEngine.evaluateSizes(
            body: .demo,
            chart: .demo
        )

        guard let closest = comparison.closestMatch else {
            return XCTFail("Expected a closest size match")
        }

        let closestDistance = abs(closest.report.score)

        for size in comparison.sizes {
            XCTAssertLessThanOrEqual(
                closestDistance,
                abs(size.report.score)
            )
        }
    }

    func testDifferentSizesProduceDifferentFitDescriptions() {
        let comparison = FitEngine.evaluateSizes(
            body: .demo,
            chart: .demo
        )

        let uniqueSummaries = Set(comparison.sizes.map(\.summary))
        XCTAssertGreaterThan(uniqueSummaries.count, 1)
    }
}
