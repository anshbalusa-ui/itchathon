import SwiftUI

struct RootView: View {
    var body: some View {
        NavigationStack {
            #if DEBUG
            if AvatarExperienceFeatures.internalPilotEnabled {
                CatalogRootView()
            } else {
                HomeView()
            }
            #else
            HomeView()
            #endif
        }
    }
}
