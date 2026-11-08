import SwiftUI

struct ClosetView: View {
  var store: ClosetStore
  var scans: AvatarScanStore
  @State private var adding = false

  var body: some View {
    Group {
      if store.garments.isEmpty {
        ContentUnavailableView {
          Label("Your closet", systemImage: "tshirt")
        } description: {
          Text("Scan clothes you own or add a product photo. Start with a shirt whose fit you love.")
        }
      } else {
        List {
          if let reference = store.reference {
            Section("Your fit reference") { row(reference) }
          }
          Section("Clothes") {
            ForEach(store.garments.filter { !$0.isReference }) { garment in
              row(garment)
            }
          }
        }
      }
    }
    .navigationTitle("Closet")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button("Add clothes", systemImage: "plus") { adding = true }
          .accessibilityIdentifier("closet.add.toolbar")
      }
    }
    .sheet(isPresented: $adding) { NavigationStack { AddGarmentView(store: store) } }
    .alert("Closet", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
      Button("OK", role: .cancel) { store.error = nil }
    } message: { Text(store.error ?? "") }
  }

  private func row(_ garment: ClosetGarment) -> some View {
    NavigationLink {
      ClosetGarmentDetailView(garment: garment, store: store, scans: scans)
    } label: {
      HStack(spacing: 16) {
        GarmentPhotoView(url: store.imageURL(for: garment))
          .frame(width: 64, height: 76)
          .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 5) {
          Text(garment.name).font(.headline)
          Text(garment.dimensions == nil ? "Photo saved · fit unknown" : "Depth scan · estimated dimensions")
            .font(.subheadline).foregroundStyle(.secondary)
          if garment.isReference { Label("My favorite fit", systemImage: "heart.fill").font(.caption).foregroundStyle(.tint) }
        }
      }
      .padding(.vertical, 4)
    }
    .swipeActions { Button("Delete", systemImage: "trash", role: .destructive) { store.delete(garment) } }
  }
}

