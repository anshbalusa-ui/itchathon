#if DEBUG
import CryptoKit
import XCTest
@testable import FitCheck

final class SyntheticArtifactCodecTests: XCTestCase {
    private func generate(_ fixture: GeometryFixtureID) async throws -> GeometryResult {
        try await SyntheticGeometryGenerator().generate(fixture)
    }

    func testSurfaceARoundTripPreservesDecodedMeshAndAuthority() async throws {
        let source = try await generate(.surfaceA)
        let bytes = try SyntheticArtifactCodec.encode(source)
        let artifact = try SyntheticArtifactCodec.decode(bytes)

        XCTAssertLessThanOrEqual(bytes.count, SyntheticArtifactCodec.maximumFileBytes)
        XCTAssertEqual(artifact.fixture, .surfaceA)
        XCTAssertEqual(artifact.identity.fixture, .surfaceA)
        XCTAssertEqual(artifact.identity.revision, 1)
        XCTAssertEqual(artifact.mesh, source.mesh)
        XCTAssertNoThrow(try artifact.validate())
    }

    func testSurfaceBRoundTripRetainsDifferentMesh() async throws {
        let a = try await generate(.surfaceA)
        let b = try await generate(.surfaceB)
        let artifact = try SyntheticArtifactCodec.decode(SyntheticArtifactCodec.encode(b))

        XCTAssertEqual(artifact.fixture, .surfaceB)
        XCTAssertEqual(artifact.mesh, b.mesh)
        XCTAssertNotEqual(artifact.mesh, a.mesh)
        XCTAssertNoThrow(try artifact.validate())
    }

    func testDeterministicEncodingHasStablePayloadDigestAndFreshArtifactIdentity() async throws {
        let result = try await generate(.surfaceA)
        let first = try SyntheticArtifactCodec.decode(SyntheticArtifactCodec.encode(result))
        let second = try SyntheticArtifactCodec.decode(SyntheticArtifactCodec.encode(result))

        XCTAssertEqual(first.identity.contentDigest, second.identity.contentDigest)
        XCTAssertNotEqual(first.identity.artifactID, second.identity.artifactID)
    }

    func testRejectsEmptyTruncatedAndMalformedData() {
        XCTAssertThrowsError(try SyntheticArtifactCodec.decode(Data())) {
            XCTAssertEqual($0 as? SyntheticArtifactFailure, .corruptArtifact)
        }
        XCTAssertThrowsError(try SyntheticArtifactCodec.decode(Data("{\"formatVersion\":1".utf8))) {
            XCTAssertEqual($0 as? SyntheticArtifactFailure, .corruptArtifact)
        }
        XCTAssertThrowsError(try SyntheticArtifactCodec.decode(Data(repeating: 0xFF, count: 128))) {
            XCTAssertEqual($0 as? SyntheticArtifactFailure, .corruptArtifact)
        }
    }

    func testRejectsOversizedFileBeforeDecoding() {
        let oversized = Data(repeating: 0, count: SyntheticArtifactCodec.maximumFileBytes + 1)
        XCTAssertThrowsError(try SyntheticArtifactCodec.decode(oversized)) {
            XCTAssertEqual($0 as? SyntheticArtifactFailure, .resourceLimit)
        }
    }

    func testRejectsPayloadTamperingAndTruncation() async throws {
        let result = try await generate(.surfaceA)
        let valid = try SyntheticArtifactCodec.encode(result)
        var altered = valid
        altered[altered.count / 2] ^= 0x01
        XCTAssertThrowsError(try SyntheticArtifactCodec.decode(altered))
        XCTAssertThrowsError(try SyntheticArtifactCodec.decode(Data(valid.dropLast())))
    }

    func testRecomputedDigestDoesNotAuthorizeChangedMesh() async throws {
        let source = try await generate(.surfaceA)
        let encoded = try SyntheticArtifactCodec.encode(source)
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let payloadText = try XCTUnwrap(envelope["payload"] as? String)
        var payload = try XCTUnwrap(Data(base64Encoded: payloadText))
        payload[8] ^= 0x01
        envelope["payload"] = payload.base64EncodedString()
        envelope["digest"] = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        let malicious = try JSONSerialization.data(withJSONObject: envelope)

        XCTAssertThrowsError(try SyntheticArtifactCodec.decode(malicious)) {
            XCTAssertEqual($0 as? SyntheticArtifactFailure, .incompatibleArtifact)
        }
    }


    func testRejectsUnknownVersionAndScannerProvenanceMetadata() async throws {
        let result = try await generate(.surfaceA)
        let encoded = try SyntheticArtifactCodec.encode(result)
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        var future = original
        future["formatVersion"] = 99
        let futureBytes = try JSONSerialization.data(withJSONObject: future)
        XCTAssertThrowsError(try SyntheticArtifactCodec.decode(futureBytes)) {
            XCTAssertEqual($0 as? SyntheticArtifactFailure, .unsupportedVersion)
        }

        var scanner = original
        scanner["provenance"] = "scanner"
        let scannerBytes = try JSONSerialization.data(withJSONObject: scanner)
        XCTAssertThrowsError(try SyntheticArtifactCodec.decode(scannerBytes)) {
            XCTAssertEqual($0 as? SyntheticArtifactFailure, .unauthorizedSource)
        }
    }
    func testScannerShapedNegativeFixtureCannotBeEncoded() async throws {
        let input = try GeometryKernel.reviewedFixture(.unverifiedSource)
        XCTAssertThrowsError(try GeometryKernel.generate(input)) {
            XCTAssertEqual($0 as? GeometryFailure, .unverifiedSource)
        }
        do {
            _ = try SyntheticArtifactCodec.encode(try GeometryKernel.generate(input))
            XCTFail("Unverified source must not produce an artifact.")
        } catch let failure as GeometryFailure {
            XCTAssertEqual(failure, .unverifiedSource)
        }
    }

    func testChangedShapeFutureHeaderIsUnsupportedBeforePayloadDecode() {
        let bytes = Data("{\"formatVersion\":999,\"artifactRevision\":1,\"futureShape\":true}".utf8)
        XCTAssertThrowsError(try SyntheticArtifactCodec.decode(bytes)) {
            XCTAssertEqual($0 as? SyntheticArtifactFailure, .unsupportedVersion)
        }
    }

    func testForgedCompatibilityCountsAndIdentityAreRejected() async throws {
        let bytes = try SyntheticArtifactCodec.encode(await generate(.surfaceA))
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        let cases: [(String, Any, SyntheticArtifactFailure)] = [
            ("artifactRevision", 2, .unsupportedVersion), ("fixtureRevision", 2, .unsupportedVersion),
            ("algorithmRevision", 2, .unsupportedVersion), ("meshSchema", 2, .unsupportedVersion),
            ("algorithm", "unreviewed-kernel", .unsupportedVersion),
            ("coordinateConvention", "left-handed", .unauthorizedSource),
            ("metresPerUnit", 0.01, .unauthorizedSource), ("provenance", "unknown", .unauthorizedSource),
            ("role", "personal-avatar", .incompatibleArtifact),
            ("rendererCapability", "personal-fit", .incompatibleArtifact),
            ("validationStatus", "physical-valid", .incompatibleArtifact),
            ("artifactID", "stale-not-an-artifact", .corruptArtifact),
            ("fixture", "real-person", .unauthorizedSource),
            ("vertexCount", Int.max, .resourceLimit), ("indexCount", Int.max, .resourceLimit),
            ("fixture", GeometryFixtureID.surfaceB.rawValue, .incompatibleArtifact)
        ]
        for (field, value, expected) in cases {
            var altered = original
            altered[field] = value
            let data = try JSONSerialization.data(withJSONObject: altered)
            XCTAssertThrowsError(try SyntheticArtifactCodec.decode(data), field) {
                XCTAssertEqual($0 as? SyntheticArtifactFailure, expected, field)
            }
        }
    }

    func testRehashedNonfiniteNormalsTopologyAndBoundsStillFailAdmission() async throws {
        let source = try await generate(.surfaceA)
        let bytes = try SyntheticArtifactCodec.encode(source)
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        let initial = try XCTUnwrap(Data(base64Encoded: XCTUnwrap(original["payload"] as? String)))
        let firstIndex = 8 + source.mesh.vertices.count * 24
        let mutations: [(inout Data) -> Void] = [
            { Self.put(Float.nan.bitPattern, at: 8, in: &$0) },
            { Self.put(Float.infinity.bitPattern, at: 8, in: &$0) },
            { Self.put(UInt32(0), at: 20, in: &$0); Self.put(UInt32(0), at: 24, in: &$0); Self.put(UInt32(0), at: 28, in: &$0) },
            { $0[firstIndex] = 255; $0[firstIndex + 1] = 255 },
            { $0[firstIndex + 2] = $0[firstIndex]; $0[firstIndex + 3] = $0[firstIndex + 1] },
            { $0.swapAt(firstIndex + 2, firstIndex + 4); $0.swapAt(firstIndex + 3, firstIndex + 5) },
            { Self.put(Float(100).bitPattern, at: $0.count - 24, in: &$0) }
        ]
        for mutate in mutations {
            var payload = initial
            mutate(&payload)
            var altered = original
            altered["payload"] = payload.base64EncodedString()
            altered["digest"] = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
            let data = try JSONSerialization.data(withJSONObject: altered)
            XCTAssertThrowsError(try SyntheticArtifactCodec.decode(data)) {
                XCTAssertEqual($0 as? SyntheticArtifactFailure, .corruptArtifact)
            }
        }
    }

    private static func put(_ value: UInt32, at offset: Int, in data: inout Data) {
        for byte in 0..<4 { data[offset + byte] = UInt8(truncatingIfNeeded: value >> (byte * 8)) }
    }
    func testCancellationIsTypedAndDoesNotReturnArtifact() async throws {
        let result = try await generate(.surfaceA)
        let bytes = try SyntheticArtifactCodec.encode(result)
        let failures = await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            var errors: [SyntheticArtifactFailure?] = []
            do { _ = try SyntheticArtifactCodec.encode(result); errors.append(nil) }
            catch { errors.append(error as? SyntheticArtifactFailure) }
            do { _ = try SyntheticArtifactCodec.decode(bytes); errors.append(nil) }
            catch { errors.append(error as? SyntheticArtifactFailure) }
            return errors
        }.value
        XCTAssertEqual(failures, [.cancelled, .cancelled])
    }
}
#endif
