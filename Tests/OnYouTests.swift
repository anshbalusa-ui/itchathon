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

  func testProductionGeneratorRefinesAndTracksIndependentMeasurements() async throws {
    let generator = BodyModelGenerator.shared
    let baselineValues = BodyMeasurements(height: 180, chest: 96, waist: 80, hips: 98, shoulders: 44)
    let baseline = try await generator.generate(baselineValues)
    func maxDelta(_ a: RendererMesh, _ b: RendererMesh) -> Float {
      zip(a.vertices, b.vertices).map { simd_distance($0.0.position, $0.1.position) }.max() ?? 0
    }
    for field in BodyMeasurementField.allCases {
      var changed = baselineValues
      changed[field] = field == .height ? 190 : min(field.range.upperBound, baselineValues[field] + 8)
      let result = try await generator.generate(changed)
      XCTAssertGreaterThan(maxDelta(result.body, baseline.body), 0.001, "\(field) must change the generated body")
      let stations: [BodyMeasurementField: Float] = [.chest: 1.30, .waist: 1.08, .hips: 0.91]
      for (dimension, station) in stations {
        XCTAssertEqual(BodyShapeKernel.circumference(result.body, at: station * Float(changed.height / 180)),
          Float(changed[dimension] / 100), accuracy: 0.02, "Changing \(field) must preserve the \(dimension) target")
      }
      let shoulders = try SmoothMeshGeometry.centralSection(points: result.body.vertices.map(\.position),
        indices: result.body.indices, y: 1.44 * Float(changed.height / 180))
      XCTAssertEqual(shoulders.width, Float(changed.shoulders / 100), accuracy: 0.012)
      XCTAssertEqual(result.body.maximum.y - result.body.minimum.y, Float(changed.height / 100), accuracy: 0.001)
    }
    for field in BodyMeasurementField.allCases {
      for edge in [field.range.lowerBound, field.range.upperBound] {
        var values = baselineValues
        values[field] = edge
        let result = try await generator.generate(values)
        XCTAssertTrue(result.body.vertices.allSatisfy { $0.position.x.isFinite && $0.position.y.isFinite && $0.position.z.isFinite })
      }
    }

    var slimValues = baselineValues
    slimValues.chest = 60; slimValues.waist = 45; slimValues.hips = 65; slimValues.shoulders = 28
    var broadValues = baselineValues
    broadValues.chest = 170; broadValues.waist = 170; broadValues.hips = 180; broadValues.shoulders = 65
    let slim = try await generator.generate(slimValues)
    let broad = try await generator.generate(broadValues)
    XCTAssertEqual(slim.body.maximum.y, broad.body.maximum.y, accuracy: 0.001)
    XCTAssertGreaterThan(maxDelta(slim.body, broad.body), 0.1)
    XCTAssertEqual(BodyShapeKernel.circumference(broad.body, at: 1.30), 1.70, accuracy: 0.05)
    XCTAssertEqual(BodyShapeKernel.circumference(broad.body, at: 1.08), 1.70, accuracy: 0.05)
    XCTAssertEqual(BodyShapeKernel.circumference(broad.body, at: 0.91), 1.80, accuracy: 0.05)
    let repeated = try await generator.generate(broadValues)
    XCTAssertEqual(broad.body.vertices.map(\.position), repeated.body.vertices.map(\.position))
    XCTAssertTrue(broad.body.vertices.allSatisfy { abs(simd_length($0.normal) - 1) < 0.001 })
    var edgeUse: [UInt64: Int] = [:]
    for offset in stride(from: 0, to: broad.body.indices.count, by: 3) {
      for edge in 0..<3 {
        let a = UInt64(broad.body.indices[offset + edge])
        let b = UInt64(broad.body.indices[offset + (edge + 1) % 3])
        let key = min(a, b) << 16 | max(a, b)
        edgeUse[key, default: 0] += 1
      }
    }
    XCTAssertTrue(edgeUse.values.allSatisfy { $0 == 2 }, "refined body remains a closed manifold")

    var invalid = baselineValues
    invalid.chest = .nan
    do {
      _ = try await generator.generate(invalid)
      XCTFail("Invalid measurements must be rejected")
    } catch { }
  }

  func testWideBodyDeformationNeverFoldsAcrossTheArmTransition() throws {
    let kernel = try BodyShapeKernel(reference: HumanShowcaseAssets.load().body)
    let samples = [
      BodyMeasurements(height: 120, chest: 170, waist: 170, hips: 180, shoulders: 28),
      BodyMeasurements(height: 180, chest: 170, waist: 170, hips: 180, shoulders: 65),
      BodyMeasurements(height: 220, chest: 60, waist: 45, hips: 65, shoulders: 28)
    ]
    for sample in samples {
      for station in stride(from: Float(0.9), through: 1.6, by: 0.025) {
        let points = (0...650).map {
          RendererVertex(position: SIMD3(Float($0) / 1000, station, 0.1), normal: SIMD3(0, 0, 1))
        }
        let strip = RendererMesh(vertices: points, indices: [], minimum: .zero, maximum: SIMD3(0.65, station, 0.1))
        let deformed = try kernel.shape(strip, to: sample)
        for index in 1..<deformed.vertices.count {
          XCTAssertGreaterThan(deformed.vertices[index].position.x, deformed.vertices[index - 1].position.x,
            "The arm transition must remain one-to-one at height \(station)")
        }
      }
    }
  }

  func testTorsoChangesPreserveFaceHandDetailAndShortsStayOnPelvis() async throws {
    let generator = BodyModelGenerator.shared
    let original = try await generator.generate(.example)
    let broad = try await generator.generate(BodyMeasurements(height: 175, chest: 116, waist: 108, hips: 120, shoulders: 49))
    for (before, after) in zip(original.body.vertices, broad.body.vertices) {
      if before.position.y > 1.57 * 175 / 180 {
        XCTAssertLessThan(simd_distance(before.position, after.position), 0.00001, "Torso inputs must not swell the generic face")
      }
      if abs(before.position.x) > 0.45 {
        XCTAssertEqual(before.position.z, after.position.z, accuracy: 0.00001, "Torso inputs must not inflate the fingers")
      }
    }
    let armIndices = original.body.vertices.indices.filter {
      let p = original.body.vertices[$0].position
      return p.x > 0.27 && (1.18 * 175 / 180 ... 1.30 * 175 / 180).contains(p.y)
    }
    let translations = armIndices.map {
      broad.body.vertices[$0].position.x - original.body.vertices[$0].position.x
    }
    let narrowest = try XCTUnwrap(translations.min()), widest = try XCTUnwrap(translations.max())
    XCTAssertLessThan(widest - narrowest, 0.001,
      "A wider chest must move the upper arm without squeezing its cross-section")
    for index in armIndices {
      XCTAssertEqual(original.body.vertices[index].position.z, broad.body.vertices[index].position.z, accuracy: 0.00001)
    }
    for shorts in [original.shorts, broad.shorts] {
      var neighbors = Array(repeating: Set<Int>(), count: shorts.vertices.count)
      var edges: [UInt64: Int] = [:]
      for face in stride(from: 0, to: shorts.indices.count, by: 3) {
        for corner in 0..<3 {
          let a = Int(shorts.indices[face + corner]), b = Int(shorts.indices[face + (corner + 1) % 3])
          neighbors[a].insert(b); neighbors[b].insert(a)
          edges[UInt64(min(a,b)) << 32 | UInt64(max(a,b)), default: 0] += 1
        }
      }
      var visited = Set<Int>(), pending = [0]
      while let vertex = pending.popLast() {
        if visited.insert(vertex).inserted { pending.append(contentsOf: neighbors[vertex]) }
      }
      XCTAssertEqual(visited.count, shorts.vertices.count, "No detached shorts fragments may appear on the hands")
      XCTAssertTrue(edges.values.allSatisfy { $0 == 1 || $0 == 2 })
      var boundary = Array(repeating: Set<Int>(), count: shorts.vertices.count)
      for (edge, uses) in edges where uses == 1 {
        let a = Int(edge >> 32), b = Int(UInt32(truncatingIfNeeded: edge))
        boundary[a].insert(b); boundary[b].insert(a)
      }
      XCTAssertTrue(boundary.allSatisfy { $0.isEmpty || $0.count == 2 })
      var boundaryVisited = Set<Int>(), openings = 0
      for seed in boundary.indices where !boundary[seed].isEmpty && !boundaryVisited.contains(seed) {
        openings += 1
        var queue = [seed]
        while let vertex = queue.popLast() {
          if boundaryVisited.insert(vertex).inserted { queue.append(contentsOf: boundary[vertex]) }
        }
      }
      XCTAssertEqual(openings, 3, "The shorts must retain a waist and two leg openings")
    }
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
