import SwiftUI

@main
struct FitCheckApp: App {
  var body: some Scene {
    WindowGroup {
      #if DEBUG
      if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("-fitcheck-") }) {
        RootView()
      } else {
        NavigationStack { FridayDemoShowcase() }
      }
      #else
      RootView()
      #endif
    }
  }
}
