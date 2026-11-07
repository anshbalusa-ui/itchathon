import SwiftUI

struct OnYouAboutView: View {
  @AppStorage("on-you.wireframe") private var wireframe = false

  var body: some View {
    Form {
      Section("Viewer") {
        Toggle("Show mesh", isOn: $wireframe)
        Text("Drag the model to rotate it. Pinch to zoom.")
          .foregroundStyle(.secondary)
      }
      Section("Measurement model") {
        Text("Height, chest, waist, hips, and shoulder width change the model’s shape. Other proportions are estimated from the base anatomy.")
        Text("This is a measurement-based approximation, not a body scan or a clothing-fit simulation.")
          .foregroundStyle(.secondary)
        Link("MakeHuman · CC0 body mesh", destination: URL(string: "https://github.com/makehumancommunity/makehuman")!)
      }
      Section("Scanned avatars") {
        Text("Object Capture reconstructs visible geometry and photo texture on your iPhone. Captured depth establishes scale automatically. Movement, hair, and clothing affect the reconstructed surface.")
      }
      Section("Your data") {
        Text("Measurements, history, garment photos, and saved scans stay on this iPhone. Raw scan photos are removed after reconstruction. No account or network connection is needed.")
      }
      Section("Garment scanning") {
        Text("GarmentIQ’s open-source landmark model runs on this iPhone. Camera depth supplies scale. Captures describe estimated dimensions, not fabric stretch or drape.")
        Link("GarmentIQ · MIT license", destination: URL(string: "https://github.com/lygitdata/GarmentIQ")!)
      }
      Section {
        NavigationLink { MeasurementGuideView() } label: { Label("How to measure", systemImage: "ruler") }
      }
    }
    .navigationTitle("About On You")
    .navigationBarTitleDisplayMode(.inline)
  }
}
