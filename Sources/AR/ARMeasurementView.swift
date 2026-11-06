import SwiftUI

struct ARMeasurementView: UIViewControllerRepresentable {
    var onMeasurement: (Double) -> Void
    var onStatus: (String) -> Void
    var onReset: () -> Void
    var resetToken: UUID

    func makeCoordinator() -> Coordinator {
        Coordinator(lastResetToken: resetToken)
    }

    func makeUIViewController(context: Context) -> ARMeasurementViewController {
        let controller = ARMeasurementViewController()
        controller.onMeasurement = onMeasurement
        controller.onStatus = onStatus
        controller.onReset = onReset
        return controller
    }

    func updateUIViewController(_ uiViewController: ARMeasurementViewController, context: Context) {
        uiViewController.onMeasurement = onMeasurement
        uiViewController.onStatus = onStatus
        uiViewController.onReset = onReset

        guard context.coordinator.lastResetToken != resetToken else { return }
        context.coordinator.lastResetToken = resetToken
        uiViewController.resetMeasurement()
    }

    final class Coordinator {
        var lastResetToken: UUID

        init(lastResetToken: UUID) {
            self.lastResetToken = lastResetToken
        }
    }
}
