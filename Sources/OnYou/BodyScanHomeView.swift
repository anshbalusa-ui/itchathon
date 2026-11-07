import SwiftUI

struct BodyScanHomeView: View {
  var store: AvatarScanStore
  var referenceHeight: Double?
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
          LabeledContent("Calibrated height", value: "\(asset.record.referenceHeightCM.formatted()) cm")
          LabeledContent("Surface width", value: centimeters(asset.record.widthM * asset.record.scale))
          LabeledContent("Surface depth", value: centimeters(asset.record.depthM * asset.record.scale))
          LabeledContent("Images", value: asset.record.imageCount.formatted())
        } header: {
          Text("Saved scan")
        } footer: {
          Text("Width includes arms and clothing. These are surface extents, not chest or waist measurements.")
        }
      } else {
        Section {
          Label("Capture your body in 3D", systemImage: "camera").font(.headline)
          Text("A helper moves around you while you stand still. On You reconstructs the photographed surface and keeps its colors and texture.")
        }
        Section("For a better scan") {
          Text("Use even light and close-fitting clothing.")
          Text("Keep your arms away from your sides and hold the same pose.")
          Text("Measure your height beforehand to check scale.")
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
      BodyScanFlowView(store: store, initialHeight: referenceHeight, onSaved: onSaved)
    }
    .confirmationDialog("Delete your saved scan?", isPresented: $confirmingDelete, titleVisibility: .visible) {
      Button("Delete scan", role: .destructive) { store.delete() }
    } message: {
      Text("This removes the 3D model from this iPhone. Your manual measurements are kept.")
    }
  }

  private func centimeters(_ value: Float) -> String {
    "\((value * 100).formatted(.number.precision(.fractionLength(1)))) cm"
  }
}
