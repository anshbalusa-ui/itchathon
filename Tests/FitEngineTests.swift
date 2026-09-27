import XCTest
@testable import FitCheck

final class FitEngineTests: XCTestCase {
    func testDemoGarmentProducesReport() {
        let report = FitEngine.evaluate(body: .demo, garment: .demo)

        XCTAssertFalse(report.dimensions.isEmpty)
        XCTAssertGreaterThan(report.score, 0)
        XCTAssertLessThanOrEqual(report.score, 100)
    }

    func testTooSmallChestIsRejected() {
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
        XCTAssertEqual(report.band, .incompatible)
    }

    func testSizeChartScoresEveryAvailableSize() {
        let comparison = FitEngine.evaluateSizes(
            body: .demo,
            chart: .demo
        )

        XCTAssertEqual(comparison.sizes.count, GarmentSizeChart.demo.sizes.count)
        XCTAssertNotNil(comparison.closestMatch)

        for size in comparison.sizes {
            XCTAssertGreaterThanOrEqual(size.report.score, 0)
            XCTAssertLessThanOrEqual(size.report.score, 100)
            XCTAssertFalse(size.summary.isEmpty)
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
