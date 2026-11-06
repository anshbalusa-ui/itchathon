import SwiftUI

struct BodyScanView: UIViewControllerRepresentable {
    var onComplete: (BodyProfile) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> BodyScanViewController {
        let controller = BodyScanViewController()
        controller.onComplete = onComplete
        controller.onCancel = onCancel
        return controller
    }

    func updateUIViewController(_ controller: BodyScanViewController, context: Context) {
        controller.onComplete = onComplete
        controller.onCancel = onCancel
    }

    static func dismantleUIViewController(_ controller: BodyScanViewController, coordinator: ()) {
        controller.stopScanning()
    }
}
