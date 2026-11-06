import SwiftUI

@main
struct OnYouApp: App {
  var body: some Scene {
    WindowGroup {
      #if DEBUG
      if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("-fitcheck-") }) {
        RootView()
      } else {
        OnYouRootView()
      }
      #else
      OnYouRootView()
      #endif
    }
  }
}
