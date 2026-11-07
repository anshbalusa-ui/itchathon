import SwiftUI

struct OnYouRootView: View {
  @State private var store = OnYouStore()
  @State private var closet = ClosetStore()
  @State private var scans = AvatarScanStore()
  @State private var selectedTab = OnYouTab.body

  var body: some View {
    TabView(selection: $selectedTab) {
      Tab("Body", systemImage: "figure.stand", value: .body) {
        NavigationStack {
          YourBodyView(store: store, scans: scans) { selectedTab = .scan }
        }
      }
      Tab("Scan", systemImage: "camera", value: .scan) {
        NavigationStack {
          BodyScanHomeView(store: scans) { selectedTab = .body }
        }
      }
      Tab("Closet", systemImage: "tshirt", value: .closet) {
        NavigationStack { ClosetView(store: closet) }
      }
      Tab("History", systemImage: "clock", value: .history) {
        NavigationStack { BodyHistoryView(store: store) { selectedTab = .body } }
      }
    }
    .tint(.blue)
    .alert("Saved data", isPresented: Binding(get: { store.storageError != nil || scans.error != nil }, set: { if !$0 { store.storageError = nil; scans.error = nil } })) {
      Button("OK", role: .cancel) { store.storageError = nil; scans.error = nil }
    } message: {
      Text(store.storageError ?? scans.error ?? "")
    }
  }
}

private enum OnYouTab: Hashable {
  case body, scan, closet, history
}
