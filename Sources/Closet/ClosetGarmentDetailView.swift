import SwiftUI

struct ClosetGarmentDetailView: View {
  var garment: ClosetGarment
  var store: ClosetStore
  var scans: AvatarScanStore
  @Environment(\.dismiss) private var dismiss
  @State private var deleting = false
  @State private var scanning = false
  @State private var scanningBody = false
  @State private var reviewingCapture = false
  @State private var capture: GarmentCaptureResult?
  @State private var tryingOn = false
  @State private var tryOnModel = TryOnModel()
  @State private var tryOnAvatar: AvatarScanAsset?
  private var current: ClosetGarment { store.garments.first(where: { $0.id == garment.id }) ?? garment }

  var body: some View {
    List {
      Section {
        if store.hasPhoto(for: current) {
          GarmentPhotoView(url: store.imageURL(for: current))
            .frame(height: 320)
            .accessibilityLabel("Photo of \(current.name)")
            .listRowBackground(Color(uiColor: .secondarySystemGroupedBackground))
        } else {
          ContentUnavailableView("Shirt photo missing",systemImage: "photo.badge.exclamationmark",
            description: Text("Retake the actual shirt to restore its preview. Saved dimensions alone can’t supply a garment image."))
            .accessibilityElement(children: .contain).accessibilityIdentifier("garment.photo-missing")
        }
      }
      Section {
        if store.hasPhoto(for: current), current.dimensions != nil, let asset = scans.asset {
          Button {
            tryOnAvatar = asset
            tryingOn = true
          } label: { Label("Try on",systemImage: "tshirt") }
            .accessibilityIdentifier("garment.tryon")
        } else if store.hasPhoto(for: current), current.dimensions != nil {
          Button("Scan your body to try this on", systemImage: "figure.stand") { scanningBody = true }
            .accessibilityIdentifier("garment.scanbody")
        }
        Button(current.dimensions == nil ? "Scan shirt dimensions" : "Retake shirt scan", systemImage: "camera") { scanning = true }
          .accessibilityIdentifier("garment.rescan")
      }
      if let dimensions = current.dimensions {
        Section("Estimated dimensions") { GarmentDimensionsView(dimensions: dimensions) }
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
      if let url = current.productURL { Section { Link("View product", destination: url) } }
      Section {
        Button("Delete garment", systemImage: "trash", role: .destructive) { deleting = true }
      }
    }
    .navigationTitle(current.name)
    .navigationBarTitleDisplayMode(.inline)
    .navigationDestination(isPresented: $tryingOn) {
      if let asset = tryOnAvatar {
        TryOnView(avatar: asset,garment: current,photoURL: store.imageURL(for: current),model: tryOnModel)
      }
    }
    .fullScreenCover(isPresented: $scanning, onDismiss: {
      if capture != nil { reviewingCapture = true }
    }) {
      NavigationStack {
        AutomaticGarmentScanView { result in capture = result }
      }
    }
    .fullScreenCover(isPresented: $reviewingCapture, onDismiss: { capture = nil }) {
      if let capture {
        GarmentCaptureReviewView(
          capture: capture,
          onCancel: { reviewingCapture = false; self.capture = nil },
          onSave: {
            do {
              try store.replaceCapture(for: current, with: capture)
              reviewingCapture = false
              self.capture = nil
              return nil
            } catch { return error.localizedDescription }
          }
        )
      }
    }
    .fullScreenCover(isPresented: $scanningBody) { BodyScanFlowView(store: scans) }
    .confirmationDialog("Delete this garment?", isPresented: $deleting, titleVisibility: .visible) {
      Button("Delete garment", role: .destructive) { store.delete(current); if store.error == nil { dismiss() } }
    }
  }
}

private struct GarmentCaptureReviewView: View {
  var capture: GarmentCaptureResult
  var onCancel: () -> Void
  var onSave: () -> String?
  @State private var saveError: String?

  var body: some View {
    NavigationStack {
      Form {
        Section {
          if let image = UIImage(data: capture.image) {
            Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: .infinity).frame(height: 280)
              .accessibilityLabel("Retaken shirt photo")
          }
        }
        Section("Estimated dimensions") {
          GarmentDimensionsView(dimensions: capture.dimensions)
          Text("Dimensions use checked garment landmarks and depth. Estimates do not measure fabric stretch or drape.")
            .foregroundStyle(.secondary)
        }
        if let saveError { Section { Text(saveError).foregroundStyle(.red) } }
      }
      .navigationTitle("Review shirt")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") { saveError = onSave() }.accessibilityIdentifier("garment.retake.save")
        }
      }
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
