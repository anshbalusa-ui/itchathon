import XCTest

final class AvatarPilotUITests: XCTestCase {
    func testDefaultLaunchPreservesLegacyHomeAndInternalOptInIsIsolated() {
        let app = XCUIApplication()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.staticTexts["My Body"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["avatar-pilot-root"].exists)
        app.terminate()

        app.launchArguments = ["-fitcheck-avatar-internal"]
        app.launch()
        #if DEBUG
        XCTAssertTrue(app.descendants(matching: .any)["avatar-pilot-root"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["My Body"].exists)
        XCTAssertEqual(app.textFields.count, 0)
        XCTAssertEqual(app.alerts.count, 0, "Metadata onboarding must not request camera permission")
        #else
        XCTAssertTrue(app.staticTexts["My Body"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["avatar-pilot-root"].exists)
        #endif
        app.terminate()
    }
}
