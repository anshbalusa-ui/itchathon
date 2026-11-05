import Foundation
import XCTest
@testable import FitCheck

final class IntegrationPrivacyManifestTests: XCTestCase {
    func testApplicationBundlePreservesRequiredReasonsWithoutDeclaringCollection() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
        let data = try Data(contentsOf: url)
        let manifest = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
        let collected = try XCTUnwrap(manifest["NSPrivacyCollectedDataTypes"] as? [[String: Any]])
        XCTAssertTrue(collected.isEmpty, "Neither module collects data off device")
        let declarations = try XCTUnwrap(manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        var reasons: [String: Set<String>] = [:]
        for declaration in declarations {
            let category = try XCTUnwrap(declaration["NSPrivacyAccessedAPIType"] as? String)
            XCTAssertNil(reasons[category], "Required-reason categories must not be duplicated")
            reasons[category] = Set(try XCTUnwrap(declaration["NSPrivacyAccessedAPITypeReasons"] as? [String]))
        }
        XCTAssertEqual(reasons["NSPrivacyAccessedAPICategorySystemBootTime"], Set(["35F9.1"]))
        XCTAssertEqual(reasons["NSPrivacyAccessedAPICategoryUserDefaults"], Set(["CA92.1"]))
        XCTAssertEqual(reasons["NSPrivacyAccessedAPICategoryFileTimestamp"], Set(["C617.1"]))
    }
}
