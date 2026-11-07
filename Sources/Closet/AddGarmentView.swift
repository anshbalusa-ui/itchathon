import PhotosUI
import SwiftUI

struct AddGarmentView: View {
  var store: ClosetStore
  @Environment(\.dismiss) private var dismiss
  @State private var selection: PhotosPickerItem?
  @State private var image: Data?
  @State private var dimensions: GarmentScanDimensions?
  @State private var name = ""
  @State private var productLink = ""
  @State private var scanning = false
  @State private var loading = false
  @State private var error: String?

  var body: some View {
    Form {
      if let image, let preview = UIImage(data: image) {
        Section {
          Image(uiImage: preview).resizable().scaledToFit().frame(maxWidth: .infinity).frame(height: 250)
            .accessibilityLabel("Garment photo")
        }
        Section {
          TextField("Name, optional", text: $name).textInputAutocapitalization(.words)
            .accessibilityIdentifier("garment.name")
          TextField("Product link, optional", text: $productLink)
            .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
            .accessibilityIdentifier("garment.link")
        }
        Section {
          Label(dimensions == nil ? "Photo only" : "Captured with depth", systemImage: dimensions == nil ? "photo" : "checkmark")
          Text(dimensions == nil
               ? "Photos and screenshots don’t establish physical scale. Save the look; scan the actual shirt to compare its dimensions."
               : "Garment landmarks and depth were checked across consistent captures. Dimensions are estimates; fabric stretch and drape aren’t measured.")
            .foregroundStyle(.secondary)
        }
      } else {
        Section {
          Label("Clothes you own", systemImage: "tshirt").font(.headline)
          Text("Lay a short-sleeved shirt flat. The camera finds the edges and depth supplies scale.")
          Button("Scan a shirt", systemImage: "camera") { scanning = true }
            .accessibilityIdentifier("garment.scan")
        }
        Section {
          Label("Something you found", systemImage: "photo").font(.headline)
          Text("Add a product photo or screenshot, then keep its shopping link with it.")
          photoPicker
        } footer: {
          Text("Your images stay on this iPhone.")
        }
      }
      if image != nil {
        Section("Replace capture") {
          Button("Scan a shirt", systemImage: "camera") { scanning = true }
          photoPicker
        }
      }
      if loading { Section { ProgressView("Preparing photo…") } }
      if let error { Section { Text(error).foregroundStyle(.red) } }
    }
    .navigationTitle(image == nil ? "Add clothes" : "Keep this garment")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
      ToolbarItem(placement: .confirmationAction) {
        Button("Save") { save() }.disabled(image == nil || loading)
          .accessibilityIdentifier("garment.save")
      }
    }
    .sheet(isPresented: $scanning) {
      NavigationStack {
        AutomaticGarmentScanView { capture in
          image = capture.image; dimensions = capture.dimensions; error = nil
        }
      }
    }
    .task(id: selection) {
      guard let selection else { return }
      loading = true; error = nil
      defer { loading = false }
      do {
        guard let data = try await selection.loadTransferable(type: Data.self) else { throw GarmentCaptureError.image }
        let processed = try await Task.detached(priority: .userInitiated) { try GarmentImageProcessor.importedPhoto(data) }.value
        try Task.checkCancellation()
        image = processed; dimensions = nil
      } catch is CancellationError { }
      catch { self.error = error.localizedDescription }
    }
  }

  private var photoPicker: some View {
    PhotosPicker(selection: $selection, matching: .images) { Label("Choose a photo", systemImage: "photo.on.rectangle") }
      .disabled(loading)
      .accessibilityIdentifier("garment.photo")
  }

  private func save() {
    guard let image else { return }
    let url = productLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : ClosetGarment.productLink(productLink)
    guard productLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || url != nil else {
      error = "Use a complete, secure product link beginning with https://."; return
    }
    let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
    do {
      try store.add(name: title.isEmpty ? (dimensions == nil ? "Saved garment" : "Scanned shirt") : title,
                    image: image, dimensions: dimensions, productURL: url)
      dismiss()
    } catch { self.error = error.localizedDescription }
  }
}
