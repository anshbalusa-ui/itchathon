import SwiftUI

struct BodyScanPrimaryButton: View {
  var title: String
  var busy = false
  var enabled = true
  var action: () -> Void

  var body: some View {
    if busy {
      HStack(spacing: 10) {
        ProgressView().tint(.white)
        Text(title).font(.headline).fixedSize(horizontal: false, vertical: true)
      }
      .foregroundStyle(.white)
      .frame(maxWidth: .infinity, minHeight: 28)
      .padding(.horizontal, 20).padding(.vertical, 16)
      .background(.tint, in: Capsule())
      .accessibilityElement(children: .combine)
    } else {
      Button(action: action) {
        Text(title)
          .font(.headline).fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, minHeight: 28)
          .padding(.vertical, 4)
      }
      .buttonStyle(.borderedProminent)
      .buttonBorderShape(.capsule)
      .controlSize(.large)
      .disabled(!enabled)
    }
  }
}
