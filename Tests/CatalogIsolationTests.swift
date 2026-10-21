import XCTest
@testable import FitCheck

final class CatalogIsolationTests: XCTestCase {
    func testInternalCatalogRequiresExactDebugOptInAndIsUnavailableInRelease() {
        XCTAssertFalse(AvatarExperienceFeatures.internalPilotEnabled(arguments: []))
        XCTAssertFalse(AvatarExperienceFeatures.internalPilotEnabled(arguments: ["fitcheck-avatar-internal"]))
        #if DEBUG
        XCTAssertTrue(AvatarExperienceFeatures.internalPilotEnabled(arguments: ["-fitcheck-avatar-internal"]))
        #else
        XCTAssertFalse(AvatarExperienceFeatures.internalPilotEnabled(arguments: ["-fitcheck-avatar-internal"]))
        #endif
    }
}
