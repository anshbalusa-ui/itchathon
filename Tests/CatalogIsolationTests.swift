import XCTest
@testable import FitCheck

final class CatalogIsolationTests: XCTestCase {
    func testInternalCatalogRequiresExactDebugOptInAndIsUnavailableInRelease() {
        XCTAssertEqual(InternalDevelopmentRoute.resolve(arguments: []), .legacy)
        XCTAssertEqual(InternalDevelopmentRoute.resolve(arguments: ["fitcheck-catalog-internal"]), .legacy)
        #if DEBUG
        XCTAssertEqual(InternalDevelopmentRoute.resolve(arguments: ["-fitcheck-catalog-internal"]), .catalog)
        #else
        XCTAssertEqual(InternalDevelopmentRoute.resolve(arguments: ["-fitcheck-catalog-internal"]), .legacy)
        #endif
    }
}
