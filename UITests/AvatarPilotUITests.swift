import XCTest

final class AvatarPilotUITests: XCTestCase {
    func testExplicitLegacyLaunchAndInternalOptInRemainIsolated() {
        let app = XCUIApplication()
        app.launchArguments = ["-fitcheck-legacy"]
        app.launch()
        #if DEBUG
        XCTAssertTrue(app.staticTexts["My Body"].waitForExistence(timeout: 5))
        #else
        XCTAssertTrue(app.descendants(matching: .any)["body.scene"].waitForExistence(timeout: 5))
        #endif
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
        XCTAssertTrue(app.descendants(matching: .any)["body.scene"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["avatar-pilot-root"].exists)
        #endif
        app.terminate()
    }
}
