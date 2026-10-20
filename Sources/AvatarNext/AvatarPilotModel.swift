#if DEBUG
import Combine
import Foundation

enum AvatarRecoveryReason: Equatable {
    case corruptedProfile
    case unsupportedSchema
    case invalidProfile
    case storageUnavailable
    case deletionFailed

    var allowsDeletion: Bool { self != .storageUnavailable }
}

enum AvatarPilotState: Equatable {
    case loading
    case entry(AvatarEntryDestination)
    case recovery(AvatarRecoveryReason)
}

/// Coordinates metadata only. Segment 0 has no supported avatar renderer.
@MainActor
final class AvatarPilotModel: ObservableObject {
    @Published private(set) var state: AvatarPilotState = .loading
    @Published private(set) var isWorking = false
    private let repository: any AvatarProfilePersisting

    init(repository: any AvatarProfilePersisting = AvatarProfileRepository()) {
        self.repository = repository
    }

    func refresh() async {
        guard !isWorking else { return }
        isWorking = true
        state = .loading
        defer { isWorking = false }
        do {
            let profile = try await repository.load()
            let destination = AvatarEntryResolver.destination(for: profile)
            state = destination == .invalidProfile
                ? .recovery(.invalidProfile) : .entry(destination)
        } catch {
            state = .recovery(Self.recoveryReason(for: error))
        }
    }

    func deleteProfile() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await repository.delete()
            state = .entry(.createAvatar)
        } catch {
            // Never report deletion success or erase the recovery controls on failure.
            state = .recovery(.deletionFailed)
        }
    }

    private static func recoveryReason(for error: Error) -> AvatarRecoveryReason {
        switch error as? AvatarProfileStorageError {
        case .corruptedProfile: return .corruptedProfile
        case .unsupportedSchema: return .unsupportedSchema
        case .invalidProfile, .invalidPreviewEvidence: return .invalidProfile
        default: return .storageUnavailable
        }
    }
}
#endif
