import SwiftUI

struct RootView: View {
    var body: some View {
        NavigationStack {
            if AvatarExperienceFeatures.internalPilotEnabled {
                AvatarPilotRootView()
            } else {
                HomeView()
            }
        }
    }
}
