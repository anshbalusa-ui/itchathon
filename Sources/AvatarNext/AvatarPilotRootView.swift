import Foundation
import SwiftUI

enum AvatarExperienceFeatures {
    static var internalPilotEnabled: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-fitcheck-avatar-internal")
        #else
        false
        #endif
    }
}

/// A truthful development-only entry point. This view cannot fabricate a
/// completed scan or an avatar. Real capture remains behind Segment 1.
struct AvatarPilotRootView: View {
    @State private var state: State = .loading
    private let repository = AvatarProfileRepository()

    private enum State {
        case loading
        case needsAvatar
        case savedMetadata
        case recovery
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "person.crop.square")
                .font(.system(size: 54))
                .accessibilityHidden(true)

            Text("Your FitCheck avatar")
                .font(.largeTitle.bold())

            switch state {
            case .loading:
                ProgressView("Checking your avatar profile")
            case .needsAvatar:
                Text("Create your avatar once, then explore clothing with an estimated fit preview.")
                    .foregroundStyle(.secondary)
                Label("A guided camera scan is being developed. Scanning isn't available in this build yet.", systemImage: "camera.viewfinder")
                privacyNote
            case .savedMetadata:
                Text("Your avatar profile is saved on this iPhone.")
                Text("The avatar viewer and garment previews are not available in this build yet.")
                    .foregroundStyle(.secondary)
                Button("Delete saved avatar", role: .destructive) {
                    deleteProfile()
                }
                privacyNote
            case .recovery:
                Text("We couldn't open your saved avatar profile.")
                Text("You can clear the unavailable local profile and try again later.")
                    .foregroundStyle(.secondary)
                Button("Clear unavailable profile", role: .destructive) {
                    deleteProfile()
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .navigationTitle("My Avatar")
        .onAppear(perform: refresh)
    }

    private var privacyNote: some View {
        Text("Your future avatar will use a local profile. Camera images and videos won't be saved by this screen.")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    private func refresh() {
        do {
            let profile = try repository.load()
            state = AvatarEntryResolver.destination(for: profile) == .savedAvatar
                ? .savedMetadata : .needsAvatar
        } catch {
            state = .recovery
        }
    }

    private func deleteProfile() {
        do {
            try repository.delete()
            state = .needsAvatar
        } catch {
            state = .recovery
        }
    }
}
