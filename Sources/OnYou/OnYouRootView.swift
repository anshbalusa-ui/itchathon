import SwiftUI

struct OnYouRootView: View {
  @State private var store: OnYouStore
  @State private var closet: ClosetStore
  @State private var scans: AvatarScanStore
  @State private var selectedTab = OnYouTab.body
  var synthetic = false

  @MainActor init(scans: AvatarScanStore? = nil, closet: ClosetStore? = nil, store: OnYouStore? = nil, synthetic: Bool = false) {
    _scans = State(initialValue: scans ?? AvatarScanStore()); _closet = State(initialValue: closet ?? ClosetStore())
    _store = State(initialValue: store ?? OnYouStore()); self.synthetic = synthetic
  }

  var body: some View {
    TabView(selection: $selectedTab) {
      Tab("Body", systemImage: "figure.stand", value: .body) {
        NavigationStack {
          YourBodyView(store: store, scans: scans, synthetic: synthetic)
        }
      }
      Tab("Closet", systemImage: "tshirt", value: .closet) {
        NavigationStack { ClosetView(store: closet, scans: scans) }
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
  case body, closet, history
}
