#if DEBUG
import XCTest

final class AvatarScannerUITests: XCTestCase {
    func testUnsupportedCameraCanBeCancelledAndOpenedAgainWithoutPermissionPrompt() {
        let app = XCUIApplication()
        app.launchArguments = ["-fitcheck-avatar-internal"]
        app.launch()
        let entry = app.buttons["Try guided capture"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        let start = app.buttons["start-guided-scan"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields.count, 0)
        start.tap()
        XCTAssertTrue(app.staticTexts["Camera unavailable"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.alerts.count, 0, "Unsupported devices must not request camera access")
        app.buttons["Cancel scan"].tap()
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
        XCTAssertTrue(app.staticTexts["Camera unavailable"].waitForExistence(timeout: 5))
        app.buttons["Cancel scan"].tap()
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        app.terminate()
    }
}
#endif
