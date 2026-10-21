import Foundation
import XCTest

final class RendererDevelopmentResourceIsolationTests: XCTestCase {
    #if !DEBUG
    func testProductionBundleContainsNoDevelopmentGeometryResources() throws {
        let resources = try XCTUnwrap(Bundle.main.resourceURL)
        let enumeration = try XCTUnwrap(FileManager.default.enumerator(
            at: resources,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ))
        for case let file as URL in enumeration {
            XCTAssertNotEqual(file.lastPathComponent, "FitCheckDevelopmentAssets")
            XCTAssertNotEqual(file.pathExtension.lowercased(), "fitmesh")
        }
    }
    #endif
}
