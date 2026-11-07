import SwiftUI

struct BodyScanHomeView: View {
  var store: AvatarScanStore
  var onSaved: () -> Void
  @State private var showingCapture = false
  @State private var confirmingDelete = false

  var body: some View {
    List {
      if store.hasUnreadableScan {
        Section {
          Text("Your saved scan couldn’t be opened. Its files have been kept. You can replace it with a new scan or delete it below.")
        }
      }
      if let asset = store.asset {
        Section {
          ScannedAvatarPreview(url: asset.url, referenceHeightCM: asset.record.referenceHeightCM)
            .frame(height: 320)
            .listRowInsets(EdgeInsets())
        }
        Section {
          LabeledContent("Captured", value: asset.record.date.formatted(date: .abbreviated, time: .shortened))
          Label(asset.record.usesDepthScale == true ? "Scaled from depth" : "Previously calibrated scan", systemImage: "checkmark")
        } header: {
          Text("Saved scan")
        } footer: {
          Text("Drag to inspect the captured surface. Clothing is part of this scan.")
        }
      } else {
        Section {
          Label("Capture your body", systemImage: "camera").font(.headline)
          Text("A helper moves around you while you stand still. On You reconstructs the photographed surface and keeps its colors and texture.")
        }
        Section("For a better scan") {
          Text("Use even light and close-fitting clothing.")
          Text("Keep your arms away from your sides and hold the same pose.")
          Text("Depth supplies scale automatically. No tape measure needed.")
        }
      }
      Section {
        Button(store.asset == nil ? "Start a scan" : "New scan", systemImage: "camera") { showingCapture = true }
          .accessibilityIdentifier("scan.open")
        if store.asset != nil || store.hasUnreadableScan {
          Button("Delete scan", systemImage: "trash", role: .destructive) { confirmingDelete = true }
        }
      } footer: {
        Text("Reconstruction runs on this iPhone. Raw capture photos are temporary. Your saved avatar stays on-device and is excluded from backups.")
      }
      if !BodyCaptureModel.isSupported {
        Section {
          Text("Capture requires a supported LiDAR iPhone. The simulator can’t record depth.")
            .foregroundStyle(.secondary)
        }
      }
    }
    .navigationTitle("Scan")
    .sheet(isPresented: $showingCapture) {
      BodyScanFlowView(store: store, onSaved: onSaved)
    }
    .confirmationDialog("Delete your saved scan?", isPresented: $confirmingDelete, titleVisibility: .visible) {
      Button("Delete scan", role: .destructive) { store.delete() }
    } message: {
      Text("This removes the captured avatar from this iPhone. Your closet is kept.")
    }
  }

}
