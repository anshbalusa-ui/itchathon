import XCTest

final class IntegrationUITests: XCTestCase {
    #if !DEBUG
    func testInternalRouteFlagsRemainLegacyInRelease() {
        let app = XCUIApplication()
        defer { app.launchArguments = []; app.terminate() }
        for flags in [
            ["-fitcheck-avatar-internal"],
            ["-fitcheck-catalog-internal"],
            ["-fitcheck-integrated-internal"],
            ["-fitcheck-avatar-internal", "-fitcheck-catalog-internal"],
            ["-fitcheck-avatar-internal", "-fitcheck-integrated-internal"],
            ["-fitcheck-catalog-internal", "-fitcheck-integrated-internal"]
        ] {
            app.terminate()
            app.launchArguments = flags
            app.launch()
            XCTAssertTrue(app.staticTexts["My Body"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.descendants(matching: .any)["internal-development-hub"].exists)
            XCTAssertFalse(app.descendants(matching: .any)["avatar-pilot-root"].exists)
            XCTAssertFalse(app.buttons["catalog.product.sample-studio.everyday-tee"].exists)
        }
    }
    #endif

    #if DEBUG
    func testIntegratedNavigationReturnsReopensAndIsolatesProductSelection() {
        let app = XCUIApplication()
        defer { app.launchArguments = []; app.terminate() }
        app.launchArguments = ["-fitcheck-integrated-internal", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let hub = app.descendants(matching: .any).matching(identifier: "internal-development-hub").firstMatch
        XCTAssertTrue(hub.waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Internal Development"].exists)
        capture(app, named: "Internal Development — synthetic hub")
        app.buttons["internal.open-avatar"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["avatar-pilot-root"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields.count, 0)
        XCTAssertEqual(app.alerts.count, 0)
        capture(app, named: "Avatar — metadata onboarding")
        app.buttons["Try guided capture"].tap()
        let start = app.buttons["start-guided-scan"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        capture(app, named: "Guided capture — introduction")
        start.tap()
        XCTAssertTrue(app.staticTexts["Camera unavailable"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.alerts.count, 0)
        capture(app, named: "Scanner — unsupported synthetic simulator")
        app.buttons["Cancel scan"].tap()
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["avatar-pilot-root"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(hub.waitForExistence(timeout: 5))
        app.buttons["internal.open-catalog"].tap()
        let everyday = app.buttons["catalog.product.sample-studio.everyday-tee"]
        XCTAssertTrue(everyday.waitForExistence(timeout: 5))
        capture(app, named: "Catalog — synthetic collection")
        everyday.tap()
        XCTAssertTrue(app.navigationBars["Everyday Tee"].waitForExistence(timeout: 5))
        let medium = app.buttons["catalog.size.medium"]
        reveal(medium, in: app)
        XCTAssertTrue(medium.isEnabled)
        medium.tap()
        expectSelection(medium, value: "Selected")
        app.navigationBars.buttons.firstMatch.tap()
        let weekend = app.buttons["catalog.product.sample-studio.weekend-tee"]
        reveal(weekend, in: app)
        weekend.tap()
        XCTAssertTrue(app.navigationBars["Weekend Tee"].waitForExistence(timeout: 5))
        let weekendMedium = app.buttons["catalog.size.medium"]
        reveal(weekendMedium, in: app)
        XCTAssertTrue(weekendMedium.isEnabled)
        expectSelection(weekendMedium, value: "Not selected")
        XCTAssertFalse(app.textFields.count > 0)
        capture(app, named: "Weekend Tee — independent size selection")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(everyday.waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(hub.waitForExistence(timeout: 5))
        app.buttons["internal.open-avatar"].tap()
        app.buttons["Try guided capture"].tap()
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Camera unavailable"].exists)
        XCTAssertEqual(app.alerts.count, 0)
        XCTAssertEqual(app.textFields.count, 0)
        capture(app, named: "Guided capture — reopened without scanner state")
    }

    func testLargeAccessibilityTextKeepsHubAndModuleNavigationUsable() {
        let app = XCUIApplication()
        defer { app.launchArguments = []; app.terminate() }
        app.launchArguments = ["-fitcheck-integrated-internal", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Internal Development"].waitForExistence(timeout: 5))
        let avatarLink = app.buttons["internal.open-avatar"]
        reveal(avatarLink, in: app)
        XCTAssertTrue(avatarLink.isHittable)
        capture(app, named: "Internal Development — accessibility text")
        avatarLink.tap()
        XCTAssertTrue(app.descendants(matching: .any)["avatar-pilot-root"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Try guided capture"].waitForExistence(timeout: 5))
        capture(app, named: "Avatar — accessibility text")
        let captureEntry = app.buttons["Try guided capture"]
        reveal(captureEntry, in: app)
        captureEntry.tap()
        let start = app.buttons["start-guided-scan"]
        reveal(start, in: app)
        start.tap()
        XCTAssertTrue(app.staticTexts["Camera unavailable"].waitForExistence(timeout: 5))
        let cancel = app.buttons["Cancel scan"]
        XCTAssertTrue(cancel.isHittable)
        capture(app, named: "Scanner recovery — accessibility text")
        cancel.tap()
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Internal Development"].waitForExistence(timeout: 5))
        let catalogLink = app.buttons["internal.open-catalog"]
        reveal(catalogLink, in: app)
        XCTAssertTrue(catalogLink.isHittable)
        catalogLink.tap()
        let product = app.buttons["catalog.product.sample-studio.everyday-tee"]
        reveal(product, in: app)
        product.tap()
        XCTAssertTrue(app.navigationBars["Everyday Tee"].waitForExistence(timeout: 5))
        reveal(app.buttons["catalog.color.navy"], in: app)
        app.scrollViews["catalog.colors"].swipeLeft()
        let cream = app.buttons["catalog.color.cream"]
        XCTAssertTrue(cream.isHittable)
        cream.tap()
        expectSelection(cream, value: "Selected")
        capture(app, named: "Catalog color — accessibility text")
        let size = app.buttons["catalog.size.medium"]
        reveal(size, in: app)
        XCTAssertTrue(size.isHittable)
        XCTAssertTrue(size.isEnabled)
        size.tap()
        expectSelection(size, value: "Selected")
        XCTAssertEqual(app.textFields.count, 0)
        capture(app, named: "Everyday Tee — accessibility text")
    }
    #endif

    private func capture(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func expectSelection(_ element: XCUIElement, value: String) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        // Lazy grids need scrolling before their offscreen controls enter the accessibility tree.
        for _ in 0..<6 {
            if element.exists && element.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        XCTAssertTrue(element.isHittable)
    }
}
