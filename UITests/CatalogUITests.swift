import XCTest

final class CatalogUITests: XCTestCase {
    func testNormalLaunchAndReleaseOptInRemainIsolated() {
        let app = XCUIApplication()
        defer { app.launchArguments = []; app.terminate() }
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.staticTexts["My Body"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["catalog.product.sample-studio.everyday-tee"].exists)
        app.terminate()
        app.launchArguments = ["-fitcheck-avatar-internal"]
        app.launch()
        #if DEBUG
        XCTAssertTrue(app.buttons["catalog.product.sample-studio.everyday-tee"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["My Body"].exists)
        #else
        XCTAssertTrue(app.staticTexts["My Body"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["catalog.product.sample-studio.everyday-tee"].exists)
        #endif
    }

    #if DEBUG
    func testProductNavigationAndAccessibleColorSizeSelection() {
        let app = launchCatalog()
        defer { app.launchArguments = []; app.terminate() }
        let product = app.buttons["catalog.product.sample-studio.everyday-tee"]
        XCTAssertTrue(product.waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields.count, 0)
        capture(app, named: "Catalog — synthetic collection")
        product.tap()
        XCTAssertTrue(app.navigationBars["Everyday Tee"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "catalog.detail.photo-unavailable").firstMatch.exists)
        capture(app, named: "Everyday Tee — missing photo")
        let medium = app.buttons["catalog.size.medium"]
        reveal(medium, in: app)
        XCTAssertTrue(medium.isEnabled)
        XCTAssertFalse(app.buttons["catalog.size.large"].isEnabled)
        medium.tap()
        expectSelection(medium, value: "Selected")
        let cream = app.buttons["catalog.color.cream"]
        XCTAssertTrue(cream.isHittable)
        cream.tap()
        expectSelection(cream, value: "Selected")
        expectSelection(medium, value: "Not selected")
        XCTAssertFalse(app.buttons["catalog.size.small"].isEnabled)
        medium.tap()
        expectSelection(medium, value: "Selected")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "20.00 USD")).firstMatch.waitForExistence(timeout: 5))
        reveal(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "20.00 USD")).firstMatch, in: app)
        capture(app, named: "Cream medium — selected variant price")
        XCTAssertEqual(app.textFields.count, 0)
        XCTAssertFalse(app.buttons["Try on"].exists)
        XCTAssertFalse(app.buttons["Buy"].exists)
    }

    func testMissingInformationAndDiscontinuedOptionsStayHonest() {
        let app = launchCatalog()
        defer { app.launchArguments = []; app.terminate() }
        let weekend = app.buttons["catalog.product.sample-studio.weekend-tee"]
        XCTAssertTrue(weekend.waitForExistence(timeout: 5))
        reveal(weekend, in: app)
        weekend.tap()
        XCTAssertTrue(app.navigationBars["Weekend Tee"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Description not provided."].exists)
        let medium = app.buttons["catalog.size.medium"]
        reveal(medium, in: app)
        medium.tap()
        expectSelection(medium, value: "Selected")
        XCTAssertTrue(app.staticTexts["Price for this size not provided."].exists)
        XCTAssertTrue(app.staticTexts["Garment measurements not provided."].exists)
        reveal(app.staticTexts["Garment measurements not provided."], in: app)
        capture(app, named: "Weekend Tee — missing information")
        app.navigationBars.buttons.firstMatch.tap()
        let archived = app.buttons["catalog.product.sample-studio.archived-tee"]
        reveal(archived, in: app)
        archived.tap()
        XCTAssertTrue(app.navigationBars["Archive Tee"].waitForExistence(timeout: 5))
        let unavailableSize = app.buttons["catalog.size.medium"]
        reveal(unavailableSize, in: app)
        XCTAssertFalse(unavailableSize.isEnabled)
        XCTAssertTrue(unavailableSize.label.contains("Discontinued"))
        capture(app, named: "Archive Tee — discontinued size")
        XCTAssertEqual(app.textFields.count, 0)
        XCTAssertEqual(app.alerts.count, 0)
    }

    private func launchCatalog() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-fitcheck-avatar-internal", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        return app
    }

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
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        for _ in 0..<5 {
            if element.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }
    #endif
}
