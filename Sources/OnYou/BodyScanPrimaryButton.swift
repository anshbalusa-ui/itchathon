import SwiftUI

struct BodyScanPrimaryButton: View {
  var title: String
  var enabled = true
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(title)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, minHeight: 24)
    }
    .buttonStyle(.borderedProminent)
    .controlSize(.large)
    .disabled(!enabled)
  }
}
