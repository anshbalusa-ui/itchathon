import XCTest
import simd
@testable import FitCheck

final class OnYouTests: XCTestCase {
  func testLocalizedInputAndUnitRoundTripsAtRangeEdges() {
    let locale = Locale(identifier: "fr_FR")
    for upper in [false, true] {
      var measurements = BodyMeasurements.example
      for field in BodyMeasurementField.allCases {
        measurements[field] = upper ? field.range.upperBound : field.range.lowerBound
      }
      let inches = Dictionary(uniqueKeysWithValues: BodyMeasurementField.allCases.map {
        ($0, (measurements[$0] / 2.54).formatted(.number.locale(locale).grouping(.never).precision(.fractionLength(0...2))))
      })
      XCTAssertEqual(BodyMeasurements.parse(inches, unit: .inches, locale: locale), measurements)
      var invalid = inches
      invalid[.height] = "185abc"
      XCTAssertNil(BodyMeasurements.parse(invalid, unit: .inches, locale: locale))
      invalid[.height] = ""
      XCTAssertNil(BodyMeasurements.parse(invalid, unit: .inches, locale: locale))
    }
  }

  func testMeasurementShapesMatchTorsoSectionsAndHeight() throws {
    let base = try HumanShowcaseAssets.load().body
    let kernel = try BodyShapeKernel(reference: base)
    let values = BodyMeasurements(height: 190, chest: 100, waist: 85, hips: 105, shoulders: 47)
    let mesh = try kernel.shape(base, to: values)
    XCTAssertEqual(mesh.maximum.y, 1.9, accuracy: 0.001)
    XCTAssertEqual(BodyShapeKernel.circumference(mesh, at: 1.30 * 190 / 180), 1.0, accuracy: 0.015)
    XCTAssertEqual(BodyShapeKernel.circumference(mesh, at: 1.08 * 190 / 180), 0.85, accuracy: 0.015)
    XCTAssertEqual(BodyShapeKernel.circumference(mesh, at: 0.91 * 190 / 180), 1.05, accuracy: 0.015)
    XCTAssertEqual(mesh.indices, base.indices)
    XCTAssertTrue(mesh.vertices.allSatisfy { abs(simd_length($0.normal) - 1) < 0.001 })
    var changed = values
    changed.waist = 105
    let wider = try kernel.shape(base, to: changed)
    XCTAssertEqual(BodyShapeKernel.circumference(wider, at: 1.08 * 190 / 180), 1.05, accuracy: 0.02)
    XCTAssertEqual(wider.maximum.y, mesh.maximum.y, accuracy: 0.001)
  }

  func testInvalidAndExtremeMeasurements() throws {
    let base = try HumanShowcaseAssets.load().body
    let kernel = try BodyShapeKernel(reference: base)
    for field in BodyMeasurementField.allCases {
      var invalid = BodyMeasurements.example
      invalid[field] = .nan
      XCTAssertFalse(invalid.isValid)
      XCTAssertThrowsError(try kernel.shape(base, to: invalid))
      for edge in [field.range.lowerBound, field.range.upperBound] {
        var extreme = BodyMeasurements.example
        extreme[field] = edge
        let shaped = try kernel.shape(base, to: extreme)
        XCTAssertTrue(shaped.vertices.allSatisfy { vertex in
          let p = vertex.position
          return p.x.isFinite && p.y.isFinite && p.z.isFinite && simd_length(vertex.normal).isFinite
        })
      }
    }
  }

  @MainActor
  func testPersistenceHistoryAndDeletionDoNotChangeCurrentBody() throws {
    let name = "OnYouTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let store = OnYouStore(defaults: defaults)
    XCTAssertNil(store.current)
    XCTAssertTrue(store.save(.example))
    var next = BodyMeasurements.example
    next.waist = 90
    XCTAssertTrue(store.save(next))
    XCTAssertEqual(store.history.count, 2)
    XCTAssertTrue(store.save(next))
    XCTAssertEqual(store.history.count, 2)
    store.delete(IndexSet(integer: 0))
    XCTAssertEqual(store.current, next)
    let reopened = OnYouStore(defaults: defaults)
    XCTAssertEqual(reopened.current, next)
    XCTAssertEqual(reopened.history.count, 1)
    XCTAssertEqual(reopened.history.first?.measurements, .example)
  }

  @MainActor
  func testCorruptStorageIsRetainedAndInvalidSaveRejected() throws {
    let name = "OnYouTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let corrupt = Data("corrupt".utf8)
    defaults.set(corrupt, forKey: "on-you.measurements.v1")
    let store = OnYouStore(defaults: defaults)
    XCTAssertNotNil(store.storageError)
    XCTAssertEqual(defaults.data(forKey: "on-you.measurements.v1"), corrupt)
    var invalid = BodyMeasurements.example
    invalid.height = -10
    XCTAssertFalse(store.save(invalid))
    XCTAssertNil(store.current)
    XCTAssertEqual(defaults.data(forKey: "on-you.measurements.v1"), corrupt)
  }
}
