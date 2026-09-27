import SwiftUI

struct ARMeasurementView: UIViewControllerRepresentable {
    var onMeasurement: (Double) -> Void
    var onStatus: (String) -> Void

    func makeUIViewController(context: Context) -> ARMeasurementViewController {
        let controller = ARMeasurementViewController()
        controller.onMeasurement = onMeasurement
        controller.onStatus = onStatus
        return controller
    }

    func updateUIViewController(_ uiViewController: ARMeasurementViewController, context: Context) {}
}
