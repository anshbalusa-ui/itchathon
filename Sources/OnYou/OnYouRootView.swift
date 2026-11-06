import SwiftUI

struct OnYouRootView: View {
  @State private var store = OnYouStore()
  @State private var selectedTab = OnYouTab.body

  var body: some View {
    TabView(selection: $selectedTab) {
      Tab("Body", systemImage: "figure.stand", value: .body) {
        NavigationStack {
          YourBodyView(store: store) { selectedTab = .measurements }
        }
      }
      Tab("Measurements", systemImage: "ruler", value: .measurements) {
        NavigationStack {
          BodyMeasurementsView(store: store) { selectedTab = .body }
        }
      }
      Tab("History", systemImage: "clock", value: .history) {
        NavigationStack { BodyHistoryView(store: store) { selectedTab = .body } }
      }
    }
    .tint(.blue)
    .alert("Measurements", isPresented: Binding(get: { store.storageError != nil }, set: { if !$0 { store.storageError = nil } })) {
      Button("OK", role: .cancel) { store.storageError = nil }
    } message: {
      Text(store.storageError ?? "")
    }
  }
}

private enum OnYouTab: Hashable {
  case body, measurements, history
}
