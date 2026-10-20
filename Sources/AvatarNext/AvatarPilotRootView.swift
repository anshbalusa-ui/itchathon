#if DEBUG
import SwiftUI

/// Internal metadata onboarding only; never requests the camera or creates a scan.
struct AvatarPilotRootView: View {
    @StateObject private var model: AvatarPilotModel
    @State private var showDeleteConfirmation = false
    @Environment(\.scenePhase) private var scenePhase

    init(repository: any AvatarProfilePersisting = AvatarProfileRepository()) {
        _model = StateObject(wrappedValue: AvatarPilotModel(repository: repository))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Label("Development preview", systemImage: "hammer")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Image(systemName: "person.crop.square")
                    .font(.system(size: 54))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)

                Text("Your FitCheck avatar")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)

                content

                Divider()
                Label("Private by design", systemImage: "lock.shield")
                    .font(.headline)
                Text("This screen does not use the camera or save photos, recordings, or depth maps. Avatar metadata stays on this iPhone and can be deleted separately from your existing measurements.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 600, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("My Avatar")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("avatar-pilot-root")
        .disabled(model.isWorking)
        .task { await model.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await model.refresh() }
            }
        }
        .alert("Delete avatar profile?", isPresented: $showDeleteConfirmation) {
            Button("Delete Avatar Profile", role: .destructive) {
                Task { await model.deleteProfile() }
            }
            Button("Cancel", role: .cancel) {
                showDeleteConfirmation = false
            }
        } message: {
            Text("This removes only the saved avatar metadata from this iPhone. Your existing body and clothing measurements will not change.")
        }
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .loading:
            ProgressView("Checking your avatar profile")
        case .entry(.createAvatar):
            VStack(alignment: .leading, spacing: 16) {
                Text("Create an avatar, without measuring yourself.")
                    .font(.title2.weight(.semibold))
                Text("Guided camera scanning is being developed. Scanning isn't available in this build yet.")
                    .foregroundStyle(.secondary)
                Text("Avatar viewing, clothing browsing, and fit estimates are not available yet.")
                    .foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("avatar-onboarding")
        case .entry(.incompleteProfile):
            VStack(alignment: .leading, spacing: 16) {
                Text("Your saved scan information is not verified.")
                    .font(.title2.weight(.semibold))
                Text("It cannot be used as a personalized avatar. Scanning and scan review are not available in this build yet.")
                    .foregroundStyle(.secondary)
                deleteButton
            }
            .accessibilityIdentifier("avatar-incomplete")
        case .entry(.previewUnavailable), .entry(.savedAvatar):
            VStack(alignment: .leading, spacing: 16) {
                Text("Avatar metadata is saved, but a preview is not available.")
                    .font(.title2.weight(.semibold))
                Text("This build has no avatar renderer or clothing catalog. Saved metadata does not establish body accuracy or garment fit.")
                    .foregroundStyle(.secondary)
                deleteButton
            }
            .accessibilityIdentifier("avatar-preview-unavailable")
        case .entry(.invalidProfile):
            recoveryContent(.invalidProfile)
        case let .recovery(reason):
            recoveryContent(reason)
        }
    }

    private var deleteButton: some View {
        Button("Delete saved avatar metadata", systemImage: "trash", role: .destructive) {
            showDeleteConfirmation = true
        }
        .accessibilityIdentifier("avatar-delete")
    }

    private func recoveryContent(_ reason: AvatarRecoveryReason) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Avatar profile unavailable", systemImage: "exclamationmark.triangle")
                .font(.title2.weight(.semibold))
            Text(recoveryMessage(reason))
                .foregroundStyle(.secondary)
            Button("Try again", systemImage: "arrow.clockwise") {
                Task { await model.refresh() }
            }
            .buttonStyle(.borderedProminent)
            if reason.allowsDeletion { deleteButton }
        }
        .accessibilityIdentifier("avatar-recovery")
    }

    private func recoveryMessage(_ reason: AvatarRecoveryReason) -> String {
        switch reason {
        case .corruptedProfile, .invalidProfile:
            return "The saved information could not be read as a valid avatar profile. Nothing has been deleted. You can try again or remove only the avatar metadata."
        case .unsupportedSchema:
            return "This profile uses a version this build cannot open. Keep it for a compatible build, or choose to delete it. Nothing has been changed."
        case .storageUnavailable:
            return "Storage could not be accessed. Unlock your iPhone and try again. Your profile has not been marked as damaged or deleted."
        case .deletionFailed:
            return "The avatar profile could not be deleted. Unlock your iPhone and try again. Deletion has not been confirmed."
        }
    }
}
#endif
