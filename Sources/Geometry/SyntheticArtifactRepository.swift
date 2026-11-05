#if DEBUG
import Darwin
import Foundation

protocol SyntheticArtifactPersisting: Sendable {
    func save(_ geometry: GeometryResult) async throws -> SyntheticArtifactIdentity
    func load() async throws -> VerifiedSyntheticArtifact?
    func delete() async throws
}

enum SyntheticArtifactRepositoryCheckpoint: Sendable {
    case afterStageCreated(URL)
    case afterPartialStageWrite(URL)
    case beforePublish(URL)
    case beforeDelete(URL)
    case afterPublish(URL)
    case afterDelete(URL)
}

/// Synchronous, narrow filesystem seam. Throwing aborts the operation at that exact boundary.
typealias SyntheticArtifactRepositoryCheckpointHook = @Sendable (SyntheticArtifactRepositoryCheckpoint) throws -> Void

actor SyntheticArtifactRepository: SyntheticArtifactPersisting {
    static let namespace = "FitCheckSyntheticGeometryS2B"
    static let artifactFilename = "reviewed-synthetic.geometry-artifact"

    private let directoryURL: URL
    private let checkpoint: SyntheticArtifactRepositoryCheckpointHook

    static let shared = SyntheticArtifactRepository(directoryURL: applicationDirectory())

    init(directoryURL: URL? = nil, checkpoint: @escaping SyntheticArtifactRepositoryCheckpointHook = { _ in }) {
        self.directoryURL = directoryURL ?? Self.applicationDirectory()
        self.checkpoint = checkpoint
    }

    private static func applicationDirectory() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).appendingPathComponent("Library/Application Support", isDirectory: true)
        return support.appendingPathComponent(namespace, isDirectory: true)
    }

    func save(_ geometry: GeometryResult) async throws -> SyntheticArtifactIdentity {
        let encoded = try SyntheticArtifactCodec.encodeWithIdentity(geometry)
        let bytes = encoded.data
        let identity = encoded.identity
        guard bytes.count <= SyntheticArtifactCodec.maximumFileBytes else { throw SyntheticArtifactFailure.resourceLimit }
        let dirFD = try openDirectory(create: true)
        defer { _ = close(dirFD) }
        let lockFD = try acquireLock(directoryFD: dirFD)
        defer { _ = flock(lockFD, LOCK_UN); _ = close(lockFD) }

        // Existing bytes are authoritative until an explicit delete. Never replace an unreadable or invalid record.
        _ = try readCommitted(directoryFD: dirFD)
        let destinationIdentity = try Self.namedIdentity(directoryFD: dirFD, name: Self.artifactFilename)
        let stageName = ".artifact-\(UUID().uuidString).stage"
        let stageFD = stageName.withCString { openat(dirFD, $0, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK, mode_t(S_IRUSR | S_IWUSR)) }
        guard stageFD >= 0 else { throw Self.mapErrno(errno) }
        let stageID: FileIdentity
        do {
            stageID = try Self.regularIdentity(fd: stageFD)
        } catch {
            _ = close(stageFD)
            throw Self.mapFailure(error)
        }
        defer { _ = close(stageFD) }
        do {
            try checkpoint(.afterStageCreated(directoryURL.appendingPathComponent(stageName)))
            try Self.checkCancellation()
            try Self.applyProtection(directory: directoryURL, name: stageName, expected: stageID)
            try Self.writeAll(bytes, fd: stageFD) {
                try checkpoint(.afterPartialStageWrite(directoryURL.appendingPathComponent(stageName)))
                try Self.checkCancellation()
            }
            guard fsync(stageFD) == 0 else { throw Self.mapErrno(errno) }
            try Self.verifyNamed(directoryFD: dirFD, name: stageName, expected: stageID)
            try Self.applyBackupExclusion(directory: directoryURL, name: stageName, expected: stageID)
            guard fsync(stageFD) == 0 else { throw Self.mapErrno(errno) }
            try Self.verifyDestination(directoryFD: dirFD, expected: destinationIdentity)
            try checkpoint(.beforePublish(directoryURL.appendingPathComponent(stageName)))
            try Self.checkCancellation()
            try verifyDirectory(dirFD)
            try Self.verifyNamed(directoryFD: dirFD, name: stageName, expected: stageID)
            _ = try readCommitted(directoryFD: dirFD)
            try Self.verifyDestination(directoryFD: dirFD, expected: destinationIdentity)
            guard stageName.withCString({ renameat(dirFD, $0, dirFD, Self.artifactFilename) }) == 0 else {
                throw Self.mapErrno(errno)
            }
            // Rename is the visibility commit point. A later fsync failure cannot
            // honestly be reported as an ordinary pre-publication failure.
            do {
                try checkpoint(.afterPublish(directoryURL.appendingPathComponent(Self.artifactFilename)))
                guard fsync(dirFD) == 0 else { throw SyntheticArtifactFailure.durabilityUncertain }
            } catch { throw SyntheticArtifactFailure.durabilityUncertain }
            return identity
        } catch {
            // Only unlink this operation's exact inode; a substituted entry is foreign and is preserved.
            try? Self.unlinkOwned(directoryFD: dirFD, name: stageName, identity: stageID)
            if let failure = error as? SyntheticArtifactFailure { throw failure }
            throw Self.mapFailure(error)
        }
    }

    func load() async throws -> VerifiedSyntheticArtifact? {
        try Self.checkCancellation()
        let dirFD = try openDirectory(create: false, allowMissing: true)
        guard dirFD >= 0 else { return nil }
        defer { _ = close(dirFD) }
        let lockFD = try acquireLock(directoryFD: dirFD)
        defer { _ = flock(lockFD, LOCK_UN); _ = close(lockFD) }
        return try readCommitted(directoryFD: dirFD)
    }

    func delete() async throws {
        try Self.checkCancellation()
        let dirFD = try openDirectory(create: false, allowMissing: true)
        guard dirFD >= 0 else { return }
        defer { _ = close(dirFD) }
        let lockFD = try acquireLock(directoryFD: dirFD)
        defer { _ = flock(lockFD, LOCK_UN); _ = close(lockFD) }
        let committedFD = Self.artifactFilename.withCString {
            openat(dirFD, $0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        }
        if committedFD < 0 {
            if errno == ENOENT { return }
            throw Self.mapErrno(errno)
        }
        defer { _ = close(committedFD) }
        // Pin the inode until unlink, preventing an unlink/recreate ABA match.
        let id = try Self.regularIdentity(fd: committedFD)
        do { try checkpoint(.beforeDelete(directoryURL.appendingPathComponent(Self.artifactFilename))) }
        catch { throw Self.mapFailure(error) }
        try Self.checkCancellation()
        try verifyDirectory(dirFD)
        let current = try Self.namedIdentity(directoryFD: dirFD, name: Self.artifactFilename)
        guard current == id, current?.size == id.size else {
            throw SyntheticArtifactFailure.conflict
        }
        guard Self.artifactFilename.withCString({ unlinkat(dirFD, $0, 0) }) == 0 else { throw Self.mapErrno(errno) }
        do {
            try checkpoint(.afterDelete(directoryURL.appendingPathComponent(Self.artifactFilename)))
            guard fsync(dirFD) == 0 else { throw SyntheticArtifactFailure.durabilityUncertain }
        } catch { throw SyntheticArtifactFailure.durabilityUncertain }
    }

    private func openDirectory(create: Bool, allowMissing: Bool = false) throws -> Int32 {
        if create {
            // Parent is an OS-selected app container (or an explicitly assigned
            // native-test root), not a user-supplied import path.
            do { try FileManager.default.createDirectory(at: directoryURL.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true) }
            catch { throw Self.mapFailure(error) }
            let path = directoryURL.path
            if mkdir(path, mode_t(S_IRWXU)) != 0, errno != EEXIST { throw Self.mapErrno(errno) }
        }
        let fd = directoryURL.path.withCString { open($0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }
        if fd < 0 {
            if allowMissing && errno == ENOENT { return -1 }
            throw Self.mapErrno(errno)
        }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR else { _ = close(fd); throw SyntheticArtifactFailure.invalidFileKind }
        do {
            try verifyDirectory(fd)
            // Exclude the entire assigned namespace, including invalid records,
            // the coordination lock and unswept interrupted stages, on every open.
            guard fchmod(fd, mode_t(S_IRWXU)) == 0 else { throw Self.mapErrno(errno) }
            try Self.setCompleteProtection(at: directoryURL)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var root = directoryURL
            try root.setResourceValues(values)
            try verifyDirectory(fd)
        } catch { _ = close(fd); throw Self.mapFailure(error) }
        return fd
    }

    private func verifyDirectory(_ fd: Int32) throws {
        var pinned = stat(), named = stat()
        guard fstat(fd, &pinned) == 0, lstat(directoryURL.path, &named) == 0 else {
            throw SyntheticArtifactFailure.conflict
        }
        guard (named.st_mode & S_IFMT) == S_IFDIR, pinned.st_dev == named.st_dev,
              pinned.st_ino == named.st_ino, pinned.st_uid == geteuid() else {
            throw SyntheticArtifactFailure.conflict
        }
    }

    private func acquireLock(directoryFD: Int32) throws -> Int32 {
        let fd = ".repository.lock".withCString { openat(directoryFD, $0, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK, mode_t(S_IRUSR | S_IWUSR)) }
        guard fd >= 0 else { throw Self.mapErrno(errno) }
        do {
            _ = try Self.regularIdentity(fd: fd)
            guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw errno == EWOULDBLOCK || errno == EAGAIN ? SyntheticArtifactFailure.conflict : Self.mapErrno(errno) }
            guard try Self.namedIdentity(directoryFD: directoryFD, name: ".repository.lock") == Self.regularIdentity(fd: fd) else { throw SyntheticArtifactFailure.conflict }
            return fd
        } catch { _ = close(fd); throw error }
    }

    private func readCommitted(directoryFD: Int32) throws -> VerifiedSyntheticArtifact? {
        try Self.checkCancellation()
        try verifyDirectory(directoryFD)
        let fd = Self.artifactFilename.withCString { openat(directoryFD, $0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK) }
        if fd < 0 {
            if errno == ENOENT { return nil }
            throw Self.mapErrno(errno)
        }
        defer { _ = close(fd) }
        let before = try Self.regularIdentity(fd: fd)
        guard before.linkCount == 1 else { throw SyntheticArtifactFailure.invalidFileKind }
        guard before.size >= 0, before.size <= Int64(SyntheticArtifactCodec.maximumFileBytes) else { throw SyntheticArtifactFailure.resourceLimit }
        let data = try Self.readBounded(fd: fd, size: Int(before.size))
        let afterRead = try Self.regularIdentity(fd: fd)
        guard afterRead == before, afterRead.size == before.size,
              try Self.namedIdentity(directoryFD: directoryFD, name: Self.artifactFilename) == before else {
            throw SyntheticArtifactFailure.conflict
        }
        let artifact = try SyntheticArtifactCodec.decode(data)
        try Self.applyProtection(directory: directoryURL, name: Self.artifactFilename, expected: before)
        try Self.applyBackupExclusion(directory: directoryURL, name: Self.artifactFilename, expected: before)
        try verifyDirectory(directoryFD)
        return artifact
    }

    private struct FileIdentity: Equatable {
        let device: UInt64
        let inode: UInt64
        let mode: UInt16
        let linkCount: UInt64
        let size: Int64

        static func == (lhs: FileIdentity, rhs: FileIdentity) -> Bool {
            lhs.device == rhs.device && lhs.inode == rhs.inode && lhs.mode == rhs.mode && lhs.linkCount == rhs.linkCount
        }
    }

    private static func identity(_ info: stat) -> FileIdentity {
        FileIdentity(device: UInt64(info.st_dev), inode: UInt64(info.st_ino), mode: UInt16(info.st_mode & S_IFMT), linkCount: UInt64(info.st_nlink), size: Int64(info.st_size))
    }

    private static func regularIdentity(fd: Int32) throws -> FileIdentity {
        var info = stat()
        guard fstat(fd, &info) == 0 else { throw mapErrno(errno) }
        let id = identity(info)
        guard id.mode == UInt16(S_IFREG), id.linkCount == 1 else { throw SyntheticArtifactFailure.invalidFileKind }
        return id
    }

    private static func namedIdentity(directoryFD: Int32, name: String) throws -> FileIdentity? {
        var info = stat()
        let result = name.withCString { fstatat(directoryFD, $0, &info, AT_SYMLINK_NOFOLLOW) }
        if result != 0 {
            if errno == ENOENT { return nil }
            throw mapErrno(errno)
        }
        let id = identity(info)
        guard id.mode == UInt16(S_IFREG), id.linkCount == 1 else { throw SyntheticArtifactFailure.invalidFileKind }
        return id
    }

    private static func verifyNamed(directoryFD: Int32, name: String, expected: FileIdentity) throws {
        guard try namedIdentity(directoryFD: directoryFD, name: name) == expected else { throw SyntheticArtifactFailure.conflict }
    }

    private static func verifyDestination(directoryFD: Int32, expected: FileIdentity?) throws {
        let current = try namedIdentity(directoryFD: directoryFD, name: Self.artifactFilename)
        guard current == expected, current?.size == expected?.size else { throw SyntheticArtifactFailure.conflict }
    }

    private static func writeAll(_ data: Data, fd: Int32, afterPartialWrite: () throws -> Void) throws {
        try data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            let split = max(1, raw.count / 2)
            var offset = 0
            while offset < split {
                let count = Darwin.write(fd, base.advanced(by: offset), split - offset)
                if count < 0 {
                    if errno == EINTR { continue }
                    throw mapErrno(errno)
                }
                guard count > 0 else { throw SyntheticArtifactFailure.storageFailure }
                offset += count
            }
            try afterPartialWrite()
            while offset < raw.count {
                let count = Darwin.write(fd, base.advanced(by: offset), raw.count - offset)
                if count < 0 {
                    if errno == EINTR { continue }
                    throw mapErrno(errno)
                }
                guard count > 0 else { throw SyntheticArtifactFailure.storageFailure }
                offset += count
            }
        }
    }

    private static func readBounded(fd: Int32, size: Int) throws -> Data {
        var data = Data(); data.reserveCapacity(size)
        var buffer = [UInt8](repeating: 0, count: min(16_384, max(1, size)))
        while true {
            try checkCancellation()
            let amount = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
            if amount < 0 { if errno == EINTR { continue }; throw mapErrno(errno) }
            if amount == 0 { break }
            guard data.count <= SyntheticArtifactCodec.maximumFileBytes - amount else { throw SyntheticArtifactFailure.resourceLimit }
            data.append(contentsOf: buffer[0..<amount])
        }
        guard data.count == size else { throw SyntheticArtifactFailure.conflict }
        return data
    }

    private static func applyProtection(directory: URL, name: String, expected: FileIdentity) throws {
        let url = directory.appendingPathComponent(name)
        guard try pathIdentity(directory: directory, name: name) == expected else { throw SyntheticArtifactFailure.conflict }
        try setCompleteProtection(at: url)
        guard try pathIdentity(directory: directory, name: name) == expected else { throw SyntheticArtifactFailure.conflict }
    }

    private static func setCompleteProtection(at url: URL) throws {
        #if os(iOS)
        do {
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
            #if !targetEnvironment(simulator)
            // The simulator accepts the API but does not expose a protection
            // class/keybag. On a device, fail closed if class A was not applied.
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let raw = (attributes[.protectionKey] as? FileProtectionType)?.rawValue
                ?? (attributes[.protectionKey] as? String)
            guard raw == FileProtectionType.complete.rawValue else { throw SyntheticArtifactFailure.storageFailure }
            #endif
        } catch { throw mapFailure(error) }
        #endif
    }

    private static func applyBackupExclusion(directory: URL, name: String, expected: FileIdentity) throws {
        let url = directory.appendingPathComponent(name)
        guard try pathIdentity(directory: directory, name: name) == expected else { throw SyntheticArtifactFailure.conflict }
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        var mutable = url
        do { try mutable.setResourceValues(values) }
        catch { throw mapFailure(error) }
        guard try pathIdentity(directory: directory, name: name) == expected else { throw SyntheticArtifactFailure.conflict }
    }

    private static func pathIdentity(directory: URL, name: String) throws -> FileIdentity? {
        let dirFD = directory.path.withCString { open($0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }
        guard dirFD >= 0 else { throw mapErrno(errno) }
        defer { _ = close(dirFD) }
        return try namedIdentity(directoryFD: dirFD, name: name)
    }

    private static func unlinkOwned(directoryFD: Int32, name: String, identity: FileIdentity) throws {
        guard try namedIdentity(directoryFD: directoryFD, name: name) == identity else { return }
        guard name.withCString({ unlinkat(directoryFD, $0, 0) }) == 0 else {
            if errno != ENOENT { throw mapErrno(errno) }
            return
        }
    }

    private static func mapErrno(_ code: Int32) -> SyntheticArtifactFailure {
        if code == ELOOP || code == EISDIR || code == ENOTDIR { return .invalidFileKind }
        if code == EWOULDBLOCK || code == EAGAIN { return .conflict }
        return .storageFailure
    }

    private static func checkCancellation() throws {
        if Task.isCancelled { throw SyntheticArtifactFailure.cancelled }
    }

    private static func mapFailure(_ error: Error) -> SyntheticArtifactFailure {
        if let failure = error as? SyntheticArtifactFailure { return failure }
        let ns = error as NSError
        if ns.domain == NSPOSIXErrorDomain { return mapErrno(Int32(ns.code)) }
        return .storageFailure
    }
}
#endif
