import SwiftUI

struct ClosetGarmentDetailView: View {
  var garment: ClosetGarment
  var store: ClosetStore
  var scans: AvatarScanStore
  @Environment(\.dismiss) private var dismiss
  @State private var deleting = false
  @State private var scanning = false
  @State private var captureError: String?

  private var current: ClosetGarment { store.garments.first(where: { $0.id == garment.id }) ?? garment }

  var body: some View {
    List {
      Section {
        GarmentPhotoView(url: store.imageURL(for: current))
          .frame(height: 320)
          .accessibilityLabel("Photo of \(current.name)")
          .listRowBackground(Color(uiColor: .secondarySystemGroupedBackground))
      }
      if let dimensions = current.dimensions {
        if let reference = store.reference, reference.id != current.id, let base = reference.dimensions {
          Section("Compared with \(reference.name)") {
            ForEach(dimensions.comparison(to: base), id: \.0) { title, value in
              LabeledContent(title, value: value)
            }
            NavigationLink("Compare photos") {
              GarmentComparisonView(garment: current, reference: reference, store: store)
            }
          }
        }
        Section {
          if current.isReference { Label("Your favorite fit", systemImage: "heart.fill") }
          else { Button("This shirt fits me well", systemImage: "heart") { store.setReference(current) } }
        } footer: {
          Text("Use a shirt you like as your fit reference. Comparisons describe estimated dimensions, not how fabric stretches or hangs on your body.")
        }
      } else {
        Section("Fit unknown") {
          Text("This photo has no physical scale. Scan the actual shirt to compare its dimensions with your favorite.")
            .foregroundStyle(.secondary)
        }
      }
      Section {
        if current.dimensions != nil, let asset = scans.asset {
          NavigationLink {
            TryOnView(avatar: asset, garment: current, photoURL: store.imageURL(for: current))
          } label: { Label("Try on", systemImage: "tshirt") }
        } else if current.dimensions != nil {
          Label("Scan your body to try this on", systemImage: "figure.stand")
            .foregroundStyle(.secondary)
        }
        Button(current.dimensions == nil ? "Scan to compare fit" : "Retake shirt scan", systemImage: "camera") { scanning = true }
      }
      if let url = current.productURL { Section { Link("View product", destination: url) } }
      Section {
        Button("Delete garment", systemImage: "trash", role: .destructive) { deleting = true }
      }
    }
    .navigationTitle(current.name)
    .navigationBarTitleDisplayMode(.inline)
    .sheet(isPresented: $scanning) {
      NavigationStack {
        AutomaticGarmentScanView { capture in
          do { try store.replaceCapture(for: current, with: capture) }
          catch { captureError = error.localizedDescription }
        }
      }
    }
    .alert("Capture couldn’t be saved", isPresented: Binding(get: { captureError != nil }, set: { if !$0 { captureError = nil } })) {
      Button("OK", role: .cancel) { captureError = nil }
    } message: { Text(captureError ?? "") }
    .confirmationDialog("Delete this garment?", isPresented: $deleting, titleVisibility: .visible) {
      Button("Delete garment", role: .destructive) { store.delete(current); if store.error == nil { dismiss() } }
    }
  }
}

private struct GarmentComparisonView: View {
  var garment: ClosetGarment
  var reference: ClosetGarment
  var store: ClosetStore

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        Text("Compare photos").font(.title2.bold())
        Text("Photos are resized using estimated dimensions. Cropping and camera angle can change how they line up.")
          .foregroundStyle(.secondary)
        if let a = garment.dimensions, let b = reference.dimensions {
          GeometryReader { geometry in
            let scale = min((geometry.size.width / 2 - 16) / max(a.sleeveSpanM, b.sleeveSpanM), 280 / max(a.lengthM, b.lengthM))
            HStack(alignment: .top, spacing: 16) {
              picture(garment, dimensions: a, scale: scale)
              picture(reference, dimensions: b, scale: scale)
            }
            .frame(maxWidth: .infinity)
          }.frame(height: 350)
        }
        Text("A flat comparison can’t predict drape, stretch, or how the garment sits on your avatar.")
          .font(.footnote).foregroundStyle(.secondary)
      }
      .padding().frame(maxWidth: .infinity, alignment: .leading)
    }
    .navigationTitle("Compare")
    .navigationBarTitleDisplayMode(.inline)
  }

  private func picture(_ item: ClosetGarment, dimensions: GarmentScanDimensions, scale: Double) -> some View {
    VStack(spacing: 12) {
      GarmentPhotoView(url: store.imageURL(for: item))
        .frame(width: dimensions.sleeveSpanM * scale, height: dimensions.lengthM * scale)
      Text(item.name).font(.subheadline.weight(.medium)).multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity, alignment: .top)
  }
}
