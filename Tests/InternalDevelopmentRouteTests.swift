import XCTest
@testable import FitCheck

final class InternalDevelopmentRouteTests: XCTestCase {
    func testRendererHasNoStandaloneOrPersistedLaunchRoute() {
        for argument in ["-fitcheck-renderer-internal", "-fitcheck-renderer", "renderer.lab"] {
            XCTAssertEqual(InternalDevelopmentRoute.resolve(arguments: [argument]), .legacy)
        }
        #if DEBUG
        XCTAssertEqual(InternalDevelopmentRoute.resolve(arguments: ["-fitcheck-integrated-internal"]), .integrated)
        #else
        XCTAssertEqual(InternalDevelopmentRoute.resolve(arguments: ["-fitcheck-integrated-internal"]), .legacy)
        #endif
    }

    func testIntegratedEntryRequiresExactOptIn() {
        for argument in ["fitcheck-integrated-internal", "-fitcheck-integrated-internal=true", "-FITCHECK-INTEGRATED-INTERNAL"] {
            XCTAssertEqual(InternalDevelopmentRoute.resolve(arguments: [argument]), .legacy)
        }
        #if DEBUG
        XCTAssertEqual(InternalDevelopmentRoute.resolve(arguments: ["FitCheck", "-fitcheck-integrated-internal"]), .integrated)
        #else
        XCTAssertEqual(InternalDevelopmentRoute.resolve(arguments: ["FitCheck", "-fitcheck-integrated-internal"]), .legacy)
        #endif
    }

    func testDistinctConflictingRoutesFailClosedRegardlessOfOrder() {
        let flags = ["-fitcheck-avatar-internal", "-fitcheck-catalog-internal", "-fitcheck-integrated-internal"]
        for first in flags {
            for second in flags where first != second {
                XCTAssertEqual(InternalDevelopmentRoute.resolve(arguments: [first, second]), .legacy)
            }
        }
        XCTAssertEqual(InternalDevelopmentRoute.resolve(arguments: flags), .legacy)
        XCTAssertEqual(InternalDevelopmentRoute.resolve(arguments: Array(flags.reversed())), .legacy)
    }

    func testRepeatingTheSameFlagIsNotAConflict() {
        let routes: [(String, InternalDevelopmentRoute)] = [
            ("-fitcheck-avatar-internal", .avatar),
            ("-fitcheck-catalog-internal", .catalog),
            ("-fitcheck-integrated-internal", .integrated)
        ]
        for (flag, route) in routes {
            #if DEBUG
            XCTAssertEqual(InternalDevelopmentRoute.resolve(arguments: [flag, "-AppleLocale", "en_US", flag]), route)
            #else
            XCTAssertEqual(InternalDevelopmentRoute.resolve(arguments: [flag, flag]), .legacy)
            #endif
        }
    }
}
