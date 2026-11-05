#if DEBUG
import Darwin
import Foundation
import XCTest
@testable import FitCheck

final class SyntheticArtifactRepositoryTests: XCTestCase {
    private var roots: [URL] = []

    override func tearDownWithError() throws {
        for root in roots { try? FileManager.default.removeItem(at: root) }
        roots.removeAll()
        try super.tearDownWithError()
    }

    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SyntheticArtifactRepository-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        roots.append(root)
        return root
    }

    private func geometry(_ fixture: GeometryFixtureID = .surfaceA) async throws -> GeometryResult {
        try await SyntheticGeometryGenerator().generate(fixture)
    }

    private func committed(_ root: URL) -> URL {
        root.appendingPathComponent(SyntheticArtifactRepository.artifactFilename)
    }

    func testRoundTripThroughColdRepositoryOwnerAndReplacement() async throws {
        let root = try directory()
        let first = SyntheticArtifactRepository(directoryURL: root)
        let original = try await geometry(.surfaceA)
        let savedA = try await first.save(original)
        let coldAValue = try await SyntheticArtifactRepository(directoryURL: root).load()
        let loadedA = try XCTUnwrap(coldAValue)
        XCTAssertEqual(loadedA.fixture, .surfaceA)
        XCTAssertEqual(loadedA.mesh, original.mesh)
        XCTAssertEqual(loadedA.identity, savedA)

        let second = try await geometry(.surfaceB)
        let savedB = try await SyntheticArtifactRepository(directoryURL: root).save(second)
        let coldValue = try await SyntheticArtifactRepository(directoryURL: root).load()
        let cold = try XCTUnwrap(coldValue)
        XCTAssertEqual(cold.fixture, .surfaceB)
        XCTAssertEqual(cold.mesh, second.mesh)
        XCTAssertEqual(cold.identity, savedB)
        XCTAssertNotEqual(savedA.artifactID, savedB.artifactID)
    }

    func testFailedStageWriteAndPublicationPreservePreviousRecordAndRetry() async throws {
        let root = try directory()
        let owner = SyntheticArtifactRepository(directoryURL: root)
        try await owner.save(geometry(.surfaceA))
        let prior = try Data(contentsOf: committed(root))
        let failure = SyntheticArtifactRepository(directoryURL: root) { point in
            if case .beforePublish = point { throw SyntheticArtifactFailure.storageFailure }
        }
        do { _ = try await failure.save(geometry(.surfaceB)); XCTFail("Injected publication boundary must fail") }
        catch { XCTAssertEqual(error as? SyntheticArtifactFailure, .storageFailure) }
        XCTAssertEqual(try Data(contentsOf: committed(root)), prior)
        try await owner.save(geometry(.surfaceB))
        let afterReplacement = try await owner.load()
        XCTAssertEqual(afterReplacement?.fixture, .surfaceB)

        let partial = SyntheticArtifactRepository(directoryURL: root) { point in
            if case .afterPartialStageWrite = point { throw SyntheticArtifactFailure.storageFailure }
        }
        let priorB = try Data(contentsOf: committed(root))
        do { _ = try await partial.save(geometry(.surfaceA)); XCTFail("Injected stage boundary must fail") }
        catch { XCTAssertEqual(error as? SyntheticArtifactFailure, .storageFailure) }
        XCTAssertEqual(try Data(contentsOf: committed(root)), priorB)
        let afterPartialFailure = try await owner.load()
        XCTAssertEqual(afterPartialFailure?.fixture, .surfaceB)
    }

    func testExistingCorruptBytesArePreservedForExplicitDeleteOnly() async throws {
        let root = try directory()
        let url = committed(root)
        let damaged = Data("{not a supported artifact".utf8)
        try damaged.write(to: url)
        let owner = SyntheticArtifactRepository(directoryURL: root)
        do { _ = try await owner.load(); XCTFail("Corrupt file must fail closed") }
        catch { XCTAssertEqual(error as? SyntheticArtifactFailure, .corruptArtifact) }
        do { _ = try await owner.save(geometry()); XCTFail("Save must preserve invalid current record") }
        catch { XCTAssertEqual(error as? SyntheticArtifactFailure, .corruptArtifact) }
        XCTAssertEqual(try Data(contentsOf: url), damaged)
        try await owner.delete()
        let afterDelete = try await owner.load()
        XCTAssertNil(afterDelete)
        _ = try await owner.save(geometry(.surfaceB))
        let afterRecovery = try await owner.load()
        XCTAssertEqual(afterRecovery?.fixture, .surfaceB)
    }

    func testUnsupportedVersionIsPreservedUntilExplicitDelete() async throws {
        let root = try directory()
        let approved = try await geometry()
        let encoded = try SyntheticArtifactCodec.encode(approved)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["formatVersion"] = 999
        let bytes = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try bytes.write(to: committed(root))
        let owner = SyntheticArtifactRepository(directoryURL: root)
        do { _ = try await owner.load(); XCTFail("Unknown format must not downgrade") }
        catch { XCTAssertEqual(error as? SyntheticArtifactFailure, .unsupportedVersion) }
        do { _ = try await owner.save(geometry(.surfaceB)); XCTFail("Unsupported current record must not be replaced") }
        catch { XCTAssertEqual(error as? SyntheticArtifactFailure, .unsupportedVersion) }
        XCTAssertEqual(try Data(contentsOf: committed(root)), bytes)
        try await owner.delete()
    }

    func testOrphanStagesAreNeverLoadedOrSwept() async throws {
        let root = try directory()
        let orphan = root.appendingPathComponent(".artifact-interrupted.stage")
        let bytes = Data("orphan foreign stage".utf8)
        try bytes.write(to: orphan)
        let loaded = try await SyntheticArtifactRepository(directoryURL: root).load()
        XCTAssertNil(loaded)
        XCTAssertEqual(try Data(contentsOf: orphan), bytes)
        try await SyntheticArtifactRepository(directoryURL: root).delete()
        XCTAssertEqual(try Data(contentsOf: orphan), bytes)
    }

    func testSubstitutionAtStageAndDestinationBoundariesPreservesForeignEntryAndPriorBytes() async throws {
        let root = try directory()
        let owner = SyntheticArtifactRepository(directoryURL: root)
        try await owner.save(geometry(.surfaceA))
        let destination = committed(root)
        let prior = try Data(contentsOf: destination)
        let foreign = Data("foreign marker".utf8)
        let outsider = root.appendingPathComponent("outsider")
        try foreign.write(to: outsider)

        let stageRace = SyntheticArtifactRepository(directoryURL: root) { point in
            guard case .afterStageCreated(let url) = point else { return }
            try FileManager.default.removeItem(at: url)
            try FileManager.default.createSymbolicLink(at: url, withDestinationURL: outsider)
        }
        do { _ = try await stageRace.save(geometry(.surfaceB)); XCTFail("Stage substitution must fail") }
        catch { XCTAssertTrue(error is SyntheticArtifactFailure) }
        let stages = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        let symlink = try XCTUnwrap(stages.first { $0.lastPathComponent.hasSuffix(".stage") })
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: symlink.path), outsider.path)
        XCTAssertEqual(try Data(contentsOf: outsider), foreign)
        XCTAssertEqual(try Data(contentsOf: destination), prior)
        try FileManager.default.removeItem(at: symlink)

        let destinationRace = SyntheticArtifactRepository(directoryURL: root) { point in
            guard case .beforePublish = point else { return }
            try FileManager.default.removeItem(at: destination)
            try foreign.write(to: destination)
        }
        do { _ = try await destinationRace.save(geometry(.surfaceB)); XCTFail("Destination replacement must fail validation") }
        catch { XCTAssertTrue(error is SyntheticArtifactFailure) }
        XCTAssertEqual(try Data(contentsOf: destination), foreign)
        XCTAssertEqual(try Data(contentsOf: outsider), foreign)
    }

    func testDeleteRaceDoesNotRemoveSubstitutedDirectoryOrContents() async throws {
        let root = try directory()
        let owner = SyntheticArtifactRepository(directoryURL: root)
        try await owner.save(geometry())
        let destination = committed(root)
        let marker = destination.appendingPathComponent("keep")
        let bytes = Data("do not recursively remove".utf8)
        let racing = SyntheticArtifactRepository(directoryURL: root) { point in
            guard case .beforeDelete = point else { return }
            try FileManager.default.removeItem(at: destination)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
            try bytes.write(to: marker)
        }
        do { try await racing.delete(); XCTFail("Substituted directory must not count as deleted") }
        catch { XCTAssertEqual(error as? SyntheticArtifactFailure, .invalidFileKind) }
        XCTAssertEqual(try Data(contentsOf: marker), bytes)
    }


    func testCommittedSymlinkAndDirectoryAreRejectedWithoutFollowingOrRecursion() async throws {
        let root = try directory()
        let target = root.appendingPathComponent("foreign")
        let marker = Data("foreign synthetic marker".utf8)
        try marker.write(to: target)
        let destination = committed(root)
        try FileManager.default.createSymbolicLink(at: destination, withDestinationURL: target)
        let owner = SyntheticArtifactRepository(directoryURL: root)
        do { _ = try await owner.load(); XCTFail("Committed symlink must be rejected") }
        catch { XCTAssertEqual(error as? SyntheticArtifactFailure, .invalidFileKind) }
        do { _ = try await owner.save(geometry()); XCTFail("Save must not replace unexpected committed entry") }
        catch { XCTAssertEqual(error as? SyntheticArtifactFailure, .invalidFileKind) }
        do { try await owner.delete(); XCTFail("Delete must not unlink unexpected committed entry") }
        catch { XCTAssertEqual(error as? SyntheticArtifactFailure, .invalidFileKind) }
        XCTAssertEqual(try Data(contentsOf: target), marker)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: destination.path), target.path)
        try FileManager.default.removeItem(at: destination)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        let nested = destination.appendingPathComponent("keep")
        try marker.write(to: nested)
        do { try await owner.delete(); XCTFail("Delete must not recursively remove directory") }
        catch { XCTAssertEqual(error as? SyntheticArtifactFailure, .invalidFileKind) }
        XCTAssertEqual(try Data(contentsOf: nested), marker)
    }
    func testConcurrentRepositoryOwnerGetsConflictWhileSharedLockIsHeld() async throws {
        let root = try directory()
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let first = SyntheticArtifactRepository(directoryURL: root) { point in
            guard case .afterStageCreated = point else { return }
            entered.signal()
            release.wait()
        }
        let initial = try await geometry(.surfaceA)
        let firstTask = Task { try await first.save(initial) }
        XCTAssertEqual(entered.wait(timeout: .now() + 5), .success)
        let second = SyntheticArtifactRepository(directoryURL: root)
        do { _ = try await second.load(); XCTFail("Independent actor must honor held directory lock") }
        catch { XCTAssertEqual(error as? SyntheticArtifactFailure, .conflict) }
        do { _ = try await second.save(geometry(.surfaceB)); XCTFail("Independent writer must honor the same lock") }
        catch { XCTAssertEqual(error as? SyntheticArtifactFailure, .conflict) }
        release.signal()
        _ = try await firstTask.value
    }

    func testBackupExclusionAndPrivateFilesystemModes() async throws {
        let root = try directory()
        let owner = SyntheticArtifactRepository(directoryURL: root)
        _ = try await owner.save(geometry())
        let url = committed(root)
        let values = try url.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
        XCTAssertEqual(try root.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let rootAttributes = try FileManager.default.attributesOfItem(atPath: root.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertEqual((rootAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        let metadata = XCTAttachment(string: "Protection class key exposed by runtime: \(attributes[.protectionKey] != nil). Physical class/keybag validation is separate.")
        metadata.name = "S2B runtime protection capability"
        metadata.lifetime = .keepAlways
        add(metadata)
    }

    #if os(iOS) && !targetEnvironment(simulator)
    func testPhysicalProtectionClassIsCompleteBeforePublication() async throws {
        let root = try directory()
        _ = try await SyntheticArtifactRepository(directoryURL: root).save(geometry())
        for url in [root, committed(root)] {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let protection = try XCTUnwrap(attributes[.protectionKey])
            let raw = (protection as? FileProtectionType)?.rawValue ?? (protection as? String)
            XCTAssertEqual(raw, FileProtectionType.complete.rawValue)
        }
    }
    #endif

    func testPostCommitDurabilityFailureIsDistinctFromPreCommitFailure() async throws {
        let root = try directory()
        let owner = SyntheticArtifactRepository(directoryURL: root)
        _ = try await owner.save(geometry(.surfaceA))
        let uncertainSave = SyntheticArtifactRepository(directoryURL: root) { point in
            if case .afterPublish = point { throw SyntheticArtifactFailure.storageFailure }
        }
        do { _ = try await uncertainSave.save(geometry(.surfaceB)); XCTFail("Commit without durability acknowledgement must be explicit") }
        catch { XCTAssertEqual(error as? SyntheticArtifactFailure, .durabilityUncertain) }
        let committedB = try await SyntheticArtifactRepository(directoryURL: root).load()
        XCTAssertEqual(committedB?.fixture, .surfaceB, "After the atomic visibility commit, loading determines actual state")
        let uncertainDelete = SyntheticArtifactRepository(directoryURL: root) { point in
            if case .afterDelete = point { throw SyntheticArtifactFailure.storageFailure }
        }
        do { try await uncertainDelete.delete(); XCTFail("Deletion without acknowledgement must not claim confirmed success") }
        catch { XCTAssertEqual(error as? SyntheticArtifactFailure, .durabilityUncertain) }
        let after = try await owner.load()
        XCTAssertNil(after)
        try await owner.delete()
        _ = try await owner.save(geometry(.surfaceA))
        let recovered = try await owner.load()
        XCTAssertEqual(recovered?.fixture, .surfaceA)
    }

    func testBlockedParentAndInvalidNamespaceDoNotCreateOrTraverseFiles() async throws {
        let root = try directory()
        let blocked = root.appendingPathComponent("blocked-parent")
        let marker = Data("unrelated parent marker".utf8)
        try marker.write(to: blocked)
        let nested = SyntheticArtifactRepository(directoryURL: blocked.appendingPathComponent("child"))
        do { _ = try await nested.save(geometry()); XCTFail("Non-directory parent must reject") }
        catch { XCTAssertTrue(error is SyntheticArtifactFailure) }
        XCTAssertEqual(try Data(contentsOf: blocked), marker)
        let alias = root.appendingPathComponent("namespace-alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: root)
        do { _ = try await SyntheticArtifactRepository(directoryURL: alias).save(geometry()); XCTFail("Assigned namespace symlink must reject") }
        catch { XCTAssertEqual(error as? SyntheticArtifactFailure, .invalidFileKind) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: committed(root).path))
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: alias.path), root.path)
    }

    func testForeignStageRegularFilesAndDirectoriesAreNeverCleanedOrPublished() async throws {
        let value = try await geometry(.surfaceA)
        let replacement = try await geometry(.surfaceB)
        for useDirectory in [false, true] {
            for boundary in 0..<3 {
                let root = try directory()
                let owner = SyntheticArtifactRepository(directoryURL: root)
                _ = try await owner.save(value)
                let previous = try Data(contentsOf: committed(root))
                let foreign = Data("foreign stage content must survive".utf8)
                let racing = SyntheticArtifactRepository(directoryURL: root) { point in
                    let path: URL
                    switch (boundary, point) {
                    case (0, .afterStageCreated(let url)), (1, .afterPartialStageWrite(let url)), (2, .beforePublish(let url)): path = url
                    default: return
                    }
                    try FileManager.default.removeItem(at: path)
                    if useDirectory {
                        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: false)
                        try foreign.write(to: path.appendingPathComponent("keep"))
                    } else { try foreign.write(to: path) }
                }
                do { _ = try await racing.save(replacement); XCTFail("Foreign staging substitution must fail closed") }
                catch { XCTAssertTrue(error is SyntheticArtifactFailure) }
                let stages = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
                let foreignPath = try XCTUnwrap(stages.first { $0.pathExtension == "stage" })
                let marker = useDirectory ? foreignPath.appendingPathComponent("keep") : foreignPath
                XCTAssertEqual(try Data(contentsOf: marker), foreign)
                XCTAssertEqual(try Data(contentsOf: committed(root)), previous)
                _ = try await owner.save(replacement)
                XCTAssertEqual(try Data(contentsOf: marker), foreign, "Retry may not sweep another operation's staging")
            }
        }
    }

    func testRootDirectorySubstitutionPreservesBothNamespaces() async throws {
        let root = try directory()
        let moved = root.appendingPathExtension("moved")
        roots.append(moved)
        let owner = SyntheticArtifactRepository(directoryURL: root)
        _ = try await owner.save(geometry(.surfaceA))
        let prior = try Data(contentsOf: committed(root))
        let foreign = Data("replacement namespace marker".utf8)
        let racing = SyntheticArtifactRepository(directoryURL: root) { point in
            guard case .beforePublish = point else { return }
            try FileManager.default.moveItem(at: root, to: moved)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
            try foreign.write(to: root.appendingPathComponent(SyntheticArtifactRepository.artifactFilename))
        }
        do { _ = try await racing.save(geometry(.surfaceB)); XCTFail("A substituted directory cannot become the publication target") }
        catch { XCTAssertEqual(error as? SyntheticArtifactFailure, .conflict) }
        XCTAssertEqual(try Data(contentsOf: committed(moved)), prior)
        XCTAssertEqual(try Data(contentsOf: committed(root)), foreign)
    }

    func testDeletionFailureAndForeignRegularReplacementArePreserved() async throws {
        let root = try directory()
        let owner = SyntheticArtifactRepository(directoryURL: root)
        _ = try await owner.save(geometry())
        let original = try Data(contentsOf: committed(root))
        let failing = SyntheticArtifactRepository(directoryURL: root) { point in
            if case .beforeDelete = point { throw SyntheticArtifactFailure.storageFailure }
        }
        do { try await failing.delete(); XCTFail("Failed deletion must not report absence") }
        catch { XCTAssertEqual(error as? SyntheticArtifactFailure, .storageFailure) }
        XCTAssertEqual(try Data(contentsOf: committed(root)), original)
        let path = committed(root)
        let foreign = Data("foreign regular file substituted at delete".utf8)
        let racing = SyntheticArtifactRepository(directoryURL: root) { point in
            guard case .beforeDelete = point else { return }
            try FileManager.default.removeItem(at: path)
            try foreign.write(to: path)
        }
        do { try await racing.delete(); XCTFail("A replacement inode must not be deleted") }
        catch { XCTAssertEqual(error as? SyntheticArtifactFailure, .conflict) }
        XCTAssertEqual(try Data(contentsOf: path), foreign)
    }

    func testSpecialFilesHardlinksAndOversizeCannotBeRead() async throws {
        let root = try directory()
        let path = committed(root)
        let owner = SyntheticArtifactRepository(directoryURL: root)
        XCTAssertEqual(mkfifo(path.path, mode_t(S_IRUSR | S_IWUSR)), 0)
        do { _ = try await owner.load(); XCTFail("FIFO must reject without blocking") }
        catch { XCTAssertEqual(error as? SyntheticArtifactFailure, .invalidFileKind) }
        try FileManager.default.removeItem(at: path)
        let target = root.appendingPathComponent("foreign-hardlink")
        let marker = Data("foreign hardlinked bytes".utf8)
        try marker.write(to: target)
        XCTAssertEqual(link(target.path, path.path), 0)
        do { _ = try await owner.load(); XCTFail("Multiply linked entry must not be consumed") }
        catch { XCTAssertEqual(error as? SyntheticArtifactFailure, .invalidFileKind) }
        do { try await owner.delete(); XCTFail("Multiply linked entry must not be removed") }
        catch { XCTAssertEqual(error as? SyntheticArtifactFailure, .invalidFileKind) }
        XCTAssertEqual(try Data(contentsOf: target), marker)
        try FileManager.default.removeItem(at: path)
        let oversized = Data(repeating: 0, count: SyntheticArtifactCodec.maximumFileBytes + 1)
        try oversized.write(to: path)
        do { _ = try await owner.load(); XCTFail("File cap must precede decoding") }
        catch { XCTAssertEqual(error as? SyntheticArtifactFailure, .resourceLimit) }
        XCTAssertEqual(try Data(contentsOf: path), oversized)
    }

    func testCancellationAfterPartialWritePreservesCommitAndCleansOnlyOwnedStage() async throws {
        let root = try directory()
        let owner = SyntheticArtifactRepository(directoryURL: root)
        let a = try await geometry(.surfaceA), b = try await geometry(.surfaceB)
        _ = try await owner.save(a)
        let previous = try Data(contentsOf: committed(root))
        let cancelling = SyntheticArtifactRepository(directoryURL: root) { point in
            if case .afterPartialStageWrite = point { withUnsafeCurrentTask { $0?.cancel() } }
        }
        let task = Task { try await cancelling.save(b) }
        do { _ = try await task.value; XCTFail("Cancelled partial writer must not publish") }
        catch { XCTAssertEqual(error as? SyntheticArtifactFailure, .cancelled) }
        XCTAssertEqual(try Data(contentsOf: committed(root)), previous)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasSuffix(".stage") })
        _ = try await owner.save(b)
        let recovered = try await owner.load()
        XCTAssertEqual(recovered?.fixture, .surfaceB)
    }
}
#endif
