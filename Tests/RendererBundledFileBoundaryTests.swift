#if DEBUG
import Darwin
import Foundation
import XCTest
@testable import FitCheck

final class RendererBundledFileBoundaryTests: XCTestCase {
    func testMissingDirectoryAndFileRemainDistinctFromInvalidGeometry() async throws {
        let fixture = try makeBundle()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let loader = RendererBundledAssetLoader(bundle: fixture.bundle)
        await expect(.missingResource, from: loader)
        try FileManager.default.createDirectory(at: fixture.resources, withIntermediateDirectories: true)
        await expect(.missingResource, from: loader)
    }

    func testDirectoryAndLeafSymlinkAreNotGeometryFiles() async throws {
        let fixture = try makeBundle()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        try FileManager.default.createDirectory(at: fixture.file, withIntermediateDirectories: true)
        let loader = RendererBundledAssetLoader(bundle: fixture.bundle)
        await expect(.unreadableResource, from: loader)
        try FileManager.default.removeItem(at: fixture.file)
        let external = fixture.directory.appendingPathComponent("external.fitmesh")
        try reviewedData().write(to: external)
        try FileManager.default.createSymbolicLink(at: fixture.file, withDestinationURL: external)
        await expect(.unreadableResource, from: loader)
    }

    func testResourceDirectorySymlinkCannotRedirectOutsideTheBundle() async throws {
        let fixture = try makeBundle()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let external = fixture.directory.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        try reviewedData().write(to: external.appendingPathComponent(fixture.file.lastPathComponent))
        try FileManager.default.createSymbolicLink(at: fixture.resources, withDestinationURL: external)
        await expect(.unreadableResource, from: RendererBundledAssetLoader(bundle: fixture.bundle))
    }

    func testNamedPipeIsRejectedWithoutWaitingForAWriter() async throws {
        let fixture = try makeBundle()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        try FileManager.default.createDirectory(at: fixture.resources, withIntermediateDirectories: true)
        XCTAssertEqual(mkfifo(fixture.file.path, 0o600), 0)
        await expect(.unreadableResource, from: RendererBundledAssetLoader(bundle: fixture.bundle))
    }

    func testOversizedFileIsRejectedBeforeHashingOrDecoding() async throws {
        let fixture = try makeBundle()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        try FileManager.default.createDirectory(at: fixture.resources, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 65_537).write(to: fixture.file)
        await expect(.sizeLimit, from: RendererBundledAssetLoader(bundle: fixture.bundle))
    }

    func testChangedButValidJSONFailsFixedDigestInsteadOfBeingDecoded() async throws {
        let fixture = try makeBundle()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        try FileManager.default.createDirectory(at: fixture.resources, withIntermediateDirectories: true)
        var changed = try reviewedData()
        changed.append(0x20)
        try changed.write(to: fixture.file)
        await expect(.integrityMismatch, from: RendererBundledAssetLoader(bundle: fixture.bundle))
    }

    func testUnregisteredResourceExtensionPathOrDigestCannotBorrowApproval() async throws {
        let base = RendererBundledAssetDescriptor.reviewedVest
        let variants = [
            RendererBundledAssetDescriptor(asset: base.asset, resourceName: "../FitCheckGeometricVest", resourceExtension: base.resourceExtension, sha256: base.sha256),
            RendererBundledAssetDescriptor(asset: base.asset, resourceName: base.resourceName, resourceExtension: "obj", sha256: base.sha256),
            RendererBundledAssetDescriptor(asset: base.asset, resourceName: base.resourceName, resourceExtension: base.resourceExtension, sha256: Array(repeating: 0, count: 32))
        ]
        for descriptor in variants {
            do {
                _ = try await RendererBundledAssetLoader().load(descriptor)
                XCTFail("Unreviewed declarations must not authorize file lookup")
            } catch let error as RendererAssetLoadFailure {
                XCTAssertEqual(error, .unsupportedAsset)
            }
        }
    }

    @MainActor
    func testAlreadyCancelledLoadDoesNotProceedToMissingFileLookup() async throws {
        let fixture = try makeBundle()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let loader = RendererBundledAssetLoader(bundle: fixture.bundle)
        let request = Task { @MainActor in try await loader.load(.reviewedVest) }
        request.cancel()
        do {
            _ = try await request.value
            XCTFail("A cancelled request must not publish geometry")
        } catch is CancellationError {
            // Cancellation wins over a missing resource and is not recast as an asset failure.
        }
    }

    private struct TestBundle {
        let directory: URL
        let bundle: Bundle
        let resources: URL
        var file: URL { resources.appendingPathComponent("FitCheckGeometricVest.fitmesh") }
    }

    private func makeBundle() throws -> TestBundle {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("R2Bundle-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("SyntheticAssets.bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleIdentifier": "com.itchathon.synthetic-assets.\(UUID().uuidString)",
            "CFBundleName": "SyntheticAssets", "CFBundlePackageType": "BNDL", "CFBundleVersion": "1"
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: url.appendingPathComponent("Info.plist"))
        let bundle = try XCTUnwrap(Bundle(url: url))
        let resources = try XCTUnwrap(bundle.resourceURL).appendingPathComponent("FitCheckDevelopmentAssets", isDirectory: true)
        return TestBundle(directory: directory, bundle: bundle, resources: resources)
    }

    private func reviewedData() throws -> Data {
        let root = try XCTUnwrap(Bundle.main.resourceURL)
        return try Data(contentsOf: root.appendingPathComponent("FitCheckDevelopmentAssets/FitCheckGeometricVest.fitmesh"))
    }

    private func expect(_ expected: RendererAssetLoadFailure, from loader: RendererBundledAssetLoader,
                        file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await loader.load(.reviewedVest)
            XCTFail("Invalid resources must not return a loaded token", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? RendererAssetLoadFailure, expected, file: file, line: line)
        }
    }
}
#endif
