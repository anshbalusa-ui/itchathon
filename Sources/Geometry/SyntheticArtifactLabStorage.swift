#if DEBUG
import Foundation

/// Test arguments select only a UUID child in the app's private test namespace.
/// No argument can supply a path, payload, personal profile or real source.
enum SyntheticArtifactLabStorage {
    static let testNamespaceArgument = "-fitcheck-synthetic-artifact-test-namespace"
    static let testSeedArgument = "-fitcheck-synthetic-artifact-test-seed"
    static let testRoot = "FitCheckSyntheticGeometryS2B-UITests"

    static func repository(arguments: [String] = CommandLine.arguments) -> any SyntheticArtifactPersisting {
        guard let index = arguments.firstIndex(of: testNamespaceArgument),
              index + 1 < arguments.count,
              let uuid = UUID(uuidString: arguments[index + 1]),
              arguments[index + 1].lowercased() == uuid.uuidString.lowercased() else {
            return SyntheticArtifactRepository.shared
        }
        let directory = URL.applicationSupportDirectory
            .appendingPathComponent(testRoot, isDirectory: true)
            .appendingPathComponent(uuid.uuidString.lowercased(), isDirectory: true)
        let repository = SyntheticArtifactRepository(directoryURL: directory)
        guard let seedIndex = arguments.firstIndex(of: testSeedArgument), seedIndex + 1 < arguments.count,
              let seed = Seed(rawValue: arguments[seedIndex + 1]) else { return repository }
        return SeededFixtureStore(repository: repository, directory: directory, seed: seed)
    }

    private enum Seed: String, Sendable { case corrupt, future }

    /// Only creates fixed negative bytes in a new isolated test namespace on its
    /// first load. Every save/load/delete still executes the real repository.
    private actor SeededFixtureStore: SyntheticArtifactPersisting {
        let repository: SyntheticArtifactRepository
        let directory: URL
        let seed: Seed
        private var seeded = false

        init(repository: SyntheticArtifactRepository, directory: URL, seed: Seed) {
            self.repository = repository
            self.directory = directory
            self.seed = seed
        }

        func save(_ geometry: GeometryResult) async throws -> SyntheticArtifactIdentity {
            try await repository.save(geometry)
        }

        func load() async throws -> VerifiedSyntheticArtifact? {
            if !seeded {
                try Task.checkCancellation()
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                        attributes: [.posixPermissions: 0o700])
                let data = seed == .corrupt ? Data("synthetic artifact corruption fixture".utf8)
                    : Data("{\"formatVersion\":999,\"artifactRevision\":1}".utf8)
                let file = directory.appendingPathComponent(SyntheticArtifactRepository.artifactFilename)
                try data.write(to: file, options: [.withoutOverwriting, .completeFileProtection])
                seeded = true
            }
            return try await repository.load()
        }

        func delete() async throws { try await repository.delete() }
    }
}
#endif
