import SwiftUI

struct OnYouAboutView: View {
  @AppStorage("on-you.wireframe") private var wireframe = false

  var body: some View {
    Form {
      Section("Viewer") {
        Toggle("Show mesh", isOn: $wireframe)
        Text("Drag to rotate and pinch to zoom. Use Front, Side, or Back to return to a fixed view.")
          .foregroundStyle(.secondary)
      }
      Section("Body model") {
        Text("Height, chest, waist, hips, and shoulder width change the model’s shape. Other proportions are estimated from the base anatomy.")
        Text("This is a measurement-based approximation, not a body scan or a clothing-fit simulation.")
          .foregroundStyle(.secondary)
        Link("MakeHuman · CC0 body mesh", destination: URL(string: "https://github.com/makehumancommunity/makehuman")!)
      }
      Section("Your data") {
        Text("Measurements and history stay on this iPhone. No account or network connection is needed.")
      }
      Section {
        NavigationLink { MeasurementGuideView() } label: { Label("How to measure", systemImage: "ruler") }
      }
    }
    .navigationTitle("About On You")
    .navigationBarTitleDisplayMode(.inline)
  }
}
