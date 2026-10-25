import XCTest
import UIKit

/// Shared existing geometry pixel proof, unchanged thresholds for both real labs.
class NativeMeshUITestCase: XCTestCase {
    #if DEBUG
    var viewportIdentifier: String { "geometry.scene" }

    struct Pixels {
        let rgba: [UInt8]
        var colored: Int {
            var count = 0
            for i in stride(from: 0, to: rgba.count, by: 4) {
                let red = Int(rgba[i]), green = Int(rgba[i + 1]), blue = Int(rgba[i + 2])
                if green > red + 8 && green > blue + 5 { count += 1 }
            }
            return count
        }
        func changed(from other: Self) -> Int {
            var count = 0
            for i in stride(from: 0, to: rgba.count, by: 4) {
                let red = abs(Int(rgba[i]) - Int(other.rgba[i]))
                let green = abs(Int(rgba[i + 1]) - Int(other.rgba[i + 1]))
                let blue = abs(Int(rgba[i + 2]) - Int(other.rgba[i + 2]))
                if max(red, max(green, blue)) > 12 { count += 1 }
            }
            return count
        }
        func difference(from other: Self) -> Double {
            var total = 0
            for i in rgba.indices where i % 4 != 3 { total += abs(Int(rgba[i]) - Int(other.rgba[i])) }
            return Double(total) / Double(rgba.count / 4 * 3)
        }
    }

    private enum SnapshotError: Error { case unavailable }

    @MainActor
    private func pixels(_ app: XCUIApplication) throws -> Pixels {
        let scene = app.descendants(matching: .any)[viewportIdentifier]
        guard scene.exists else { throw SnapshotError.unavailable }
        let image = try XCTUnwrap(app.screenshot().image.cgImage)
        let scale = CGFloat(image.width) / app.frame.width
        let rect = scene.frame.insetBy(dx: 4, dy: 4)
        guard rect.width > 0, rect.height > 0, app.frame.contains(rect) else { throw SnapshotError.unavailable }
        let crop = CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
        let cropped = try XCTUnwrap(image.cropping(to: crop))
        var data = [UInt8](repeating: 0, count: 96 * 96 * 4)
        try data.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: 96, height: 96, bitsPerComponent: 8, bytesPerRow: 96 * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(cropped, in: CGRect(x: 0, y: 0, width: 96, height: 96))
        }
        return Pixels(rgba: data)
    }

    @MainActor
    func rendered(_ app: XCUIApplication) throws -> Pixels {
        let predicate = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard app.descendants(matching: .any)[self.viewportIdentifier].exists,
                  let image = try? self.pixels(app) else { return false }
            return image.colored > 80
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [predicate], timeout: 15), .completed, "Actual generated Metal surface pixels must be visible")
        return try pixels(app)
    }

    @MainActor
    @discardableResult
    func changed(_ app: XCUIApplication, from reference: Pixels) throws -> Pixels {
        let predicate = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let image = try? self.pixels(app) else { return false }
            return image.colored > 80 && image.changed(from: reference) > 40
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [predicate], timeout: 15), .completed, "Real mesh geometry, not only its title, must change")
        return try pixels(app)
    }

    @MainActor
    func matches(_ app: XCUIApplication, reference: Pixels) throws {
        let predicate = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let image = try? self.pixels(app) else { return false }
            return image.colored > 80 && image.difference(from: reference) < 0.6
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [predicate], timeout: 15), .completed, "Reset/recovery must restore the actual deterministic surface")
    }

    @MainActor
    func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    #endif
}
