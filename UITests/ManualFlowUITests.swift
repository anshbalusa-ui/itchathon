import XCTest

final class ManualFlowUITests: XCTestCase {
  func testManualBodyFavoriteCandidateAndResults() {
    let app = XCUIApplication()
    app.launch()
    deleteSavedDataIfPresent(app)

    app.staticTexts["My Body"].tap()
    enter("100", into: "Chest circumference in centimeters", app: app)
    enter("46", into: "Shoulder width in centimeters", app: app)
    enter("45", into: "Torso length in centimeters", app: app)
    enter("90", into: "Waist circumference in centimeters", app: app)
    app.buttons["Save"].tap()
    XCTAssertTrue(app.staticTexts["Measurements saved"].waitForExistence(timeout: 5))

    app.staticTexts["My Fit"].tap()
    enter("Favorite", into: "Garment name", app: app)
    enter("60", into: "Chest width in centimeters", app: app)
    enter("50", into: "Shoulders in centimeters", app: app)
    enter("72", into: "Length in centimeters", app: app)
    app.buttons["Save"].tap()
    XCTAssertTrue(app.staticTexts["Favorite"].waitForExistence(timeout: 5))

    app.staticTexts["Check a Garment"].tap()
    enter("Candidate", into: "Garment name", app: app)
    enter("63", into: "Chest width in centimeters", app: app)
    enter("53", into: "Shoulders in centimeters", app: app)
    enter("78", into: "Length in centimeters", app: app)
    app.buttons["Save"].tap()
    XCTAssertTrue(app.staticTexts["View Results"].waitForExistence(timeout: 5))

    app.staticTexts["View Results"].tap()
    let chestScore = app.descendants(matching: .any)["chest-score"]
    XCTAssertTrue(chestScore.waitForExistence(timeout: 5))
    XCTAssertTrue((chestScore.value as? String)?.contains("+27 relative to Body") == true)
    app.buttons["Favorite"].tap()
    XCTAssertTrue((chestScore.value as? String)?.contains("+50 relative to Favorite") == true)

    app.terminate()
    app.launch()
    XCTAssertTrue(app.staticTexts["Measurements saved"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Favorite"].exists)
    XCTAssertTrue(app.staticTexts["Candidate"].exists)
    XCTAssertTrue(app.buttons["Calculate Results"].exists)

    app.staticTexts["My Body"].tap()
    let chest = app.textFields["Chest circumference in centimeters"]
    XCTAssertEqual(chest.value as? String, "100")
    chest.tap()
    chest.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 3) + "105")
    app.buttons["Cancel"].tap()
    app.staticTexts["My Body"].tap()
    XCTAssertEqual(app.textFields["Chest circumference in centimeters"].value as? String, "100")
    app.buttons["Cancel"].tap()

    deleteSavedDataIfPresent(app)
    XCTAssertTrue(app.staticTexts["Add your measurements"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["Calculate Results"].exists)
  }

  private func enter(_ value: String, into label: String, app: XCUIApplication) {
    let field = app.textFields[label]
    XCTAssertTrue(field.waitForExistence(timeout: 5), "Missing field: \(label)")
    field.tap()
    field.typeText(value)
  }

  private func deleteSavedDataIfPresent(_ app: XCUIApplication) {
    let delete = app.buttons["Delete FitCheck measurements"]
    guard app.staticTexts["Measurements saved"].exists
            || app.staticTexts["Favorite"].exists
            || delete.exists else { return }
    for _ in 0..<5 {
      if delete.isHittable { break }
      app.swipeUp()
    }
    XCTAssertTrue(delete.isHittable)
    delete.tap()
    app.buttons["Delete Measurements"].tap()
    app.swipeDown()
  }
}
