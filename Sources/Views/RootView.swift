import SwiftUI

struct RootView: View {
    var body: some View {
        NavigationStack {
            #if DEBUG
            switch InternalDevelopmentRoute.current {
            case .legacy:
                HomeView()
            case .avatar:
                AvatarPilotRootView()
            case .catalog:
                CatalogRootView()
            case .integrated:
                InternalDevelopmentHub()
            }
            #else
            HomeView()
            #endif
        }
    }
}
