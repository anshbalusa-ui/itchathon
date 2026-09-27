import SwiftUI

@main
struct FitCheckApp: App {
    @StateObject private var store = ProfileStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
        }
    }
}
