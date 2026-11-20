import SwiftUI

struct BodyScanReviewView: View {
  var url: URL
  var referenceHeightCM: Double
  var preparedScene: PreparedAvatarScene?
  var retake: () -> Void
  var useScan: () -> Void
  @State private var reviewNoteHeight: CGFloat = 96
  @Environment(\.dynamicTypeSize) private var typeSize

  var body: some View {
    GeometryReader { geometry in
      let wide = geometry.size.width > geometry.size.height
      let layout = wide ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
      layout {
        ScannedAvatarPreview(url: url, referenceHeightCM: referenceHeightCM, preparedScene: preparedScene)
          .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        ScrollView {
          VStack(alignment: .leading, spacing: 6) {
            Text("Check your scan")
              .font(.headline)
              .accessibilityAddTraits(.isHeader)
            Text("Drag to turn. Pinch to zoom. Check the head, arms, and feet.")
              .font(.callout).foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(16)
          .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { reviewNoteHeight = $0 }
        }
        .frame(width: wide ? geometry.size.width * 0.44 : nil,
               height: wide ? nil : min(reviewNoteHeight, geometry.size.height / 4))
        .scrollBounceBehavior(.basedOnSize)
        .background(Color(uiColor: .secondarySystemBackground))
      }
      .safeAreaInset(edge: .bottom, spacing: 0) {
        reviewActions
          .padding(.horizontal, 16)
          .padding(.bottom, 8)
          .background(Color(uiColor: .secondarySystemBackground))
      }
    }
  }

  private var reviewActions: some View {
    let retakeButton = Button("Retake", action: retake)
      .buttonStyle(.bordered)
      .controlSize(.large)
      .accessibilityIdentifier("scan.review.retake")
    let use = BodyScanPrimaryButton(title: "Use this scan", action: useScan)
      .accessibilityIdentifier("scan.review.use")
    return Group {
      if typeSize.isAccessibilitySize {
        VStack(spacing: 8) { use; retakeButton.frame(maxWidth: .infinity) }
      } else {
        ViewThatFits(in: .horizontal) {
          HStack(spacing: 12) { retakeButton; use }
          VStack(spacing: 8) { use; retakeButton.frame(maxWidth: .infinity) }
        }
      }
    }
  }

}
