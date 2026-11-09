import SwiftUI

struct ScannedAvatarPreview: View {
  var url: URL
  var referenceHeightCM: Double
  var preparedScene: PreparedAvatarScene? = nil
  @State private var loaded: PreparedAvatarScene?
  @State private var failure: String?
  @State private var attempt = UUID()
  @Environment(\.scenePhase) private var scenePhase

  private struct Request: Equatable {
    var url: URL
    var height: Double
    var attempt: UUID
  }

  var body: some View {
    Group {
      if let ready = preparedScene ?? loaded {
        BodySceneView(measurements: .example,scan: ScannedBodySource(url: url,scene: ready),isActive: scenePhase == .active)
      } else if let failure {
        ContentUnavailableView {
          Label("Avatar unavailable",systemImage: "figure.stand")
        } description: { Text(failure) } actions: {
          Button("Retry 3D preview") { attempt = UUID() }
            .accessibilityIdentifier("body.preview.retry")
        }
      } else { ProgressView("Opening your saved avatar…") }
    }
    .background(Color(uiColor: .secondarySystemGroupedBackground))
    .task(id: Request(url: url,height: referenceHeightCM,attempt: attempt)) {
      guard preparedScene == nil else { return }
      loaded = nil; failure = nil
      do {
        let ready = try await PreparedAvatarScene.load(url: url,referenceHeightCM: referenceHeightCM)
        try Task.checkCancellation()
        loaded = ready
      } catch is CancellationError { }
      catch {
        guard !Task.isCancelled else { return }
        failure = "The saved textured model couldn’t be opened. Retry, or retake the scan from the Body tab. Your saved data is unchanged."
      }
    }
    .onDisappear { loaded = nil }
  }
}
