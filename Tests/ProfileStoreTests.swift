import Foundation
import XCTest
@testable import FitCheck

@MainActor
final class ProfileStoreTests: XCTestCase {
  private func freshDefaults() -> UserDefaults {
    let defaults = UserDefaults(suiteName: "fitcheck-tests-\(UUID().uuidString)")!
    return defaults
  }

  private var body: BodyProfile {
    BodyProfile(
      chestCircumference: 1.00,
      waistCircumference: 0.90,
      shoulderWidth: 0.46,
      torsoLength: 0.45
    )
  }

  private var favorite: GarmentProfile {
    GarmentProfile(name: "Favorite", chestFlat: 0.60, shoulderWidth: 0.50, length: 0.72)
  }

  private var candidate: GarmentProfile {
    GarmentProfile(name: "Candidate", chestFlat: 0.63, shoulderWidth: 0.53, length: 0.78)
  }

  func testLegacyBodySurvivesAndSavedProfilesReload() throws {
    let defaults = freshDefaults()
    defaults.set(try JSONEncoder().encode(body), forKey: "fitcheck.bodyProfile")

    let store = ProfileStore(defaults: defaults)
    XCTAssertEqual(store.bodyProfile.chestCircumference, 1.00)
    try store.saveGarment(favorite, role: .preferred)
    try store.saveGarment(candidate, role: .candidate)
    try store.evaluateCurrentGarment()
    XCTAssertEqual(store.lastReport?.dimensions.map(\.signedScore), [50, 50, 50])

    let relaunched = ProfileStore(defaults: defaults)
    XCTAssertEqual(relaunched.bodyProfile.chestCircumference, 1.00)
    XCTAssertEqual(relaunched.preferredGarment, favorite)
    XCTAssertEqual(relaunched.currentGarment, candidate)
    XCTAssertNil(relaunched.lastReport)
  }

  func testChangesInvalidateReportsAndDeletionRemovesOnlyFitCheckData() throws {
    let defaults = freshDefaults()
    defaults.set("keep", forKey: "unrelated.preference")
    let store = ProfileStore(defaults: defaults)
    try store.saveBody(body)
    try store.saveGarment(favorite, role: .preferred)
    try store.saveGarment(candidate, role: .candidate)
    try store.evaluateCurrentGarment()
    XCTAssertNotNil(store.lastReport)

    let chart = GarmentSizeChart(
      garmentName: "Shirt",
      category: .tshirt,
      sizes: [GarmentSizeVariant(label: "M", chestFlat: 0.60, waistFlat: 0, shoulderWidth: 0.50, length: 0.72)],
      measurementBasis: .finishedGarment,
      sourceNote: "Measured label"
    )
    try store.saveSizeChart(chart)
    try store.evaluateAvailableSizes()
    XCTAssertNotNil(store.sizeComparison)

    var edited = candidate
    edited.length = 0.80
    try store.saveGarment(edited, role: .candidate)
    XCTAssertNil(store.lastReport)
    XCTAssertNil(store.sizeComparison)
    XCTAssertEqual(ProfileStore(defaults: defaults).currentGarment, edited)

    store.deleteMeasurements()
    XCTAssertFalse(store.bodyProfile.isUsable)
    XCTAssertNil(store.preferredGarment)
    XCTAssertFalse(store.currentGarment.isUsable)
    XCTAssertNil(store.currentSizeChart)
    XCTAssertNil(store.lastReport)
    XCTAssertNil(store.sizeComparison)
    XCTAssertEqual(defaults.string(forKey: "unrelated.preference"), "keep")
    XCTAssertFalse(ProfileStore(defaults: defaults).bodyProfile.isUsable)
  }

  func testRejectsBodyRecommendationChartWithoutReplacingSavedChart() throws {
    let defaults = freshDefaults()
    let store = ProfileStore(defaults: defaults)
    let finished = GarmentSizeChart(
      garmentName: "Shirt",
      category: .tshirt,
      sizes: [GarmentSizeVariant(label: "M", chestFlat: 0.60, waistFlat: 0, shoulderWidth: 0.50, length: 0.72)],
      measurementBasis: .finishedGarment,
      sourceNote: "Measured label"
    )
    try store.saveSizeChart(finished)
    var bodyChart = finished
    bodyChart.measurementBasis = .bodyRecommendation
    XCTAssertThrowsError(try store.saveSizeChart(bodyChart))
    XCTAssertEqual(store.currentSizeChart, finished)
  }
}
