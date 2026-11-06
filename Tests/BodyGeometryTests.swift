import XCTest
@testable import FitCheck

final class BodyGeometryTests: XCTestCase {
    func testEqualWidthAndDepthProducesCircleCircumference() throws {
        let circumference = try BodyGeometry.circumference(width: 2, depth: 2)

        XCTAssertEqual(circumference, 2 * Double.pi, accuracy: 1e-12)
    }

    func testKnownEllipseCircumference() throws {
        let circumference = try BodyGeometry.circumference(width: 2, depth: 1)

        XCTAssertEqual(circumference, 4.844224110273838, accuracy: 1e-8)
    }

    func testSwappingWidthAndDepthPreservesCircumference() throws {
        let widthAsFront = try BodyGeometry.circumference(width: 0.42, depth: 0.31)
        let depthAsFront = try BodyGeometry.circumference(width: 0.31, depth: 0.42)

        XCTAssertEqual(widthAsFront, depthAsFront, accuracy: 1e-14)
    }

    func testRejectsNonPositiveAndNonFiniteSpans() {
        let invalidSpans: [(Double, Double)] = [
            (0, 1), (1, 0), (-1, 1), (1, -1),
            (.nan, 1), (1, .nan), (.infinity, 1), (1, .infinity),
            (-.infinity, 1), (1, -.infinity)
        ]

        for (width, depth) in invalidSpans {
            XCTAssertThrowsError(try BodyGeometry.circumference(width: width, depth: depth),
                                 "Expected rejection for width=\(width), depth=\(depth)")
        }
    }

    func testFiniteExtremeSpansThrowWhenCircumferenceOverflows() {
        XCTAssertThrowsError(try BodyGeometry.circumference(width: .greatestFiniteMagnitude,
                                                            depth: .greatestFiniteMagnitude))
    }

    func testLeastNonzeroSpansProduceFinitePositiveCircumference() throws {
        let circumference = try BodyGeometry.circumference(width: .leastNonzeroMagnitude,
                                                           depth: .leastNonzeroMagnitude)

        XCTAssertTrue(circumference.isFinite)
        XCTAssertGreaterThan(circumference, 0)
    }
}
