import SwiftUI

struct RootView: View {
    var body: some View {
        #if DEBUG
        switch InternalDevelopmentRoute.current {
        case .legacy:
            LegacyHomeRoot()
        case .avatar:
            NavigationStack { AvatarPilotRootView() }
        case .catalog:
            NavigationStack { CatalogRootView() }
        case .integrated:
            NavigationStack { InternalDevelopmentHub() }
        }
        #else
        LegacyHomeRoot()
        #endif
    }
}

private struct LegacyHomeRoot: View {
    @StateObject private var store = ProfileStore()

    var body: some View {
        NavigationStack {
            HomeView()
        }
        .environmentObject(store)
    }
}
