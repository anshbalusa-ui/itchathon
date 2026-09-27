import UIKit
import ARKit
import AVFoundation
import CoreImage
import CoreVideo
import simd

final class BodyScanViewController: UIViewController, ARSessionDelegate {
    var onComplete: ((BodyProfile) -> Void)?
    var onCancel: (() -> Void)?

    private enum Stage {
        case permission, coachingFront, markingFront, coachingSide, markingSide, review, probeCoaching, probeMarking
    }

    private struct FrozenBodyFrame {
        let image: CVPixelBuffer
        let depth: CVPixelBuffer
        let confidence: CVPixelBuffer
        let intrinsics: simd_float3x3
        let imageSize: CGSize
        let viewportSize: CGSize
        let imageToView: CGAffineTransform
    }

    private struct MeasurementPair {
        let first: SIMD3<Float>
        let second: SIMD3<Float>
        var span: Double { Double(simd_distance(first, second)) }
    }

    private let liveView = ARSCNView(frame: .zero)
    private var session: ARSession { liveView.session }
    private let imageView = UIImageView()
    private let markerView = UIView()
    private let statusLabel = UILabel()
    private let valueLabel = UILabel()
    private let tapeField = UITextField()
    private var buttons: [UIButton] = []
    private var endpointMarkers: [UIView] = []
    private var stage: Stage = .permission
    private var frozen: FrozenBodyFrame?
    private var pairPoints: [SIMD3<Float>] = []
    private var completed: [String: Double] = [:]
    private var probePoints: [SIMD3<Float>] = []
    private var probeDistance: Double?
    private var probeError: Double?
    private var renderImage: UIImage?
    private let imageContext = CIContext(options: [.cacheIntermediates: false])
    private var needsRetake = false
    private var didCancel = false
    private var didComplete = false

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation { .portrait }

    private var specs: [(key: String, label: String)] {
        let all: [(key: String, label: String)] = stage == .markingFront || stage == .coachingFront
            ? [("chestWidth", "Chest width — widest point across chest"), ("waistWidth", "Waist width — level with navel"), ("shoulderWidth", "Outer shoulder to outer shoulder"), ("torsoLength", "Suprasternal notch to navel")]
            : [("chestDepth", "Chest depth — side view"), ("waistDepth", "Waist depth — level with navel")]
        return all.filter { completed[$0.key] == nil }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        session.delegate = self
        configureViews()
        checkPermissionAndStart()
        NotificationCenter.default.addObserver(self, selector: #selector(appDidEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateFrozenRendering()
    }

    private func configureViews() {
        liveView.translatesAutoresizingMaskIntoConstraints = false
        liveView.automaticallyUpdatesLighting = false
        liveView.backgroundColor = .black
        view.addSubview(liveView)
        NSLayoutConstraint.activate([
            liveView.leadingAnchor.constraint(equalTo: view.leadingAnchor), liveView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            liveView.topAnchor.constraint(equalTo: view.topAnchor), liveView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleToFill
        imageView.isUserInteractionEnabled = true
        imageView.isHidden = true
        view.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor), imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: view.topAnchor), imageView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        markerView.translatesAutoresizingMaskIntoConstraints = false
        markerView.isUserInteractionEnabled = false
        markerView.backgroundColor = .clear
        view.addSubview(markerView)
        NSLayoutConstraint.activate([
            markerView.leadingAnchor.constraint(equalTo: view.leadingAnchor), markerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            markerView.topAnchor.constraint(equalTo: view.topAnchor), markerView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        imageView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(imageTapped(_:))))

        let panel = UIStackView()
        panel.axis = .vertical
        panel.spacing = 10
        panel.alignment = .fill
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.backgroundColor = UIColor.black.withAlphaComponent(0.78)
        panel.isLayoutMarginsRelativeArrangement = true
        panel.layoutMargins = UIEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        view.addSubview(panel)
        NSLayoutConstraint.activate([
            panel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            panel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            panel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10)
        ])
        statusLabel.numberOfLines = 0
        statusLabel.textColor = .white
        statusLabel.font = .preferredFont(forTextStyle: .headline)
        panel.addArrangedSubview(statusLabel)
        valueLabel.numberOfLines = 0
        valueLabel.textColor = .white
        valueLabel.font = .preferredFont(forTextStyle: .subheadline)
        panel.addArrangedSubview(valueLabel)
        tapeField.placeholder = "Optional tape distance (cm)"
        tapeField.accessibilityLabel = "Known tape distance in centimeters"
        tapeField.keyboardType = .decimalPad
        tapeField.textColor = .white
        tapeField.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        tapeField.isHidden = true
        tapeField.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        panel.addArrangedSubview(tapeField)
        tapeField.addTarget(self, action: #selector(tapeDistanceChanged), for: .editingChanged)
        for titles in [["Freeze", "Mark", "Undo", "Retake"], ["Continue", "Probe", "Cancel"]] {
            let row = UIStackView()
            row.axis = .horizontal
            row.spacing = 8
            row.distribution = .fillEqually
            panel.addArrangedSubview(row)
            for title in titles {
                let button = UIButton(type: .system)
                button.setTitle(title, for: .normal)
                button.accessibilityLabel = title == "Mark" ? "Mark two endpoints" : title
                button.setTitleColor(.white, for: .normal)
                button.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.85)
                button.layer.cornerRadius = 8
                button.titleLabel?.font = .preferredFont(forTextStyle: .body)
                button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
                button.addTarget(self, action: #selector(controlTapped(_:)), for: .touchUpInside)
                row.addArrangedSubview(button)
                buttons.append(button)
            }
        }
        updateInterface()
    }

    private func checkPermissionAndStart() {
        guard ARWorldTrackingConfiguration.isSupported,
              ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) else {
            presentIssue("Depth scanning is unavailable on this device. Enter measurements manually.")
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: startSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
                DispatchQueue.main.async {
                    guard let self else { return }
                    guard allowed else { self.presentIssue("Camera access was denied. Allow camera access in Settings or enter measurements manually."); return }
                    self.startSession()
                }
            }
        case .denied, .restricted:
            presentIssue("Camera access is required. Allow access in Settings or enter measurements manually.")
        @unknown default:
            presentIssue("Camera access is unavailable. Enter measurements manually.")
        }
    }

    private func startSession() {
        guard ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) else {
            presentIssue("Scene depth is unsupported. Enter measurements manually.")
            return
        }
        let configuration = ARWorldTrackingConfiguration()
        configuration.frameSemantics.insert(.sceneDepth)
        session.delegate = self
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        if stage == .permission { stage = .coachingFront }
        updateInterface()
    }


    func sessionWasInterrupted(_ session: ARSession) {
        DispatchQueue.main.async { [weak self] in self?.handleInterruption("The scan was interrupted. Retake the current view before continuing.") }
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        DispatchQueue.main.async { [weak self] in
            self?.handleInterruption("Tracking restarted. Retake the current view before continuing.")
        }
    }

    private func handleInterruption(_ message: String) {
        let interruptedStage = stage
        clearFrozen()
        pairPoints.removeAll()
        probePoints.removeAll()
        switch interruptedStage {
        case .probeCoaching, .probeMarking:
            probeDistance = nil
            probeError = nil
            stage = .probeCoaching
        case .coachingFront, .markingFront:
            ["chestWidth", "waistWidth", "shoulderWidth", "torsoLength"].forEach { completed.removeValue(forKey: $0) }
            stage = .coachingFront
        case .coachingSide, .markingSide, .review:
            ["chestDepth", "waistDepth"].forEach { completed.removeValue(forKey: $0) }
            stage = .coachingSide
        case .permission:
            stage = .permission
        }
        needsRetake = true
        updateInterface()
        presentStatus(message)
    }

    @objc private func controlTapped(_ sender: UIButton) {
        switch sender.currentTitle {
        case "Use Scan": continueOrUse()
        case "Freeze": freezeCurrentFrame()
        case "Mark": beginMarking()
        case "Undo": undo()
        case "Retake": retake()
        case "Continue": continueOrUse()
        case "Probe": startProbe()
        case "Cancel": cancelScan()
        default: break
        }
    }

    private func freezeCurrentFrame() {
        guard !needsRetake else {
            presentStatus("The scan was interrupted. Press Retake to deliberately restart this view.")
            return
        }
        guard let frame = session.currentFrame, frame.camera.trackingState == .normal else {
            presentStatus("Tracking is not normal yet. Move slowly until tracking stabilizes, then freeze.")
            return
        }
        guard let depthData = frame.sceneDepth, let confidence = depthData.confidenceMap else {
            presentStatus("A coherent scene-depth frame with confidence data is unavailable. Try again or enter measurements manually.")
            return
        }
        let viewportSize = view.bounds.size
        guard viewportSize.width > 0, viewportSize.height > 0 else {
            presentStatus("The camera view is not ready yet. Try freezing again.")
            return
        }
        let transform = frame.displayTransform(for: .portrait, viewportSize: viewportSize)
        let size = CGSize(width: CVPixelBufferGetWidth(frame.capturedImage), height: CVPixelBufferGetHeight(frame.capturedImage))
        guard let stillImage = makeImage(from: frame.capturedImage) else {
            presentStatus("The frozen camera image could not be displayed. Try again or enter measurements manually.")
            return
        }
        frozen = FrozenBodyFrame(image: frame.capturedImage, depth: depthData.depthMap, confidence: confidence,
                                 intrinsics: frame.camera.intrinsics, imageSize: size, viewportSize: viewportSize,
                                 imageToView: transform)
        session.pause()
        pairPoints.removeAll()
        probePoints.removeAll()
        renderImage = stillImage
        imageView.isHidden = false
        updateFrozenRendering()
        updateInterface()
        presentStatus("Frame frozen. Tap Mark, then tap the two visible endpoints.")
    }

    private func makeImage(from buffer: CVPixelBuffer) -> UIImage? {
        let image = CIImage(cvPixelBuffer: buffer)
        guard let cg = imageContext.createCGImage(image, from: image.extent) else { return nil }
        return UIImage(cgImage: cg, scale: 1, orientation: .up)
    }

    private func updateFrozenRendering() {
        guard let frozen, let cg = renderImage?.cgImage else { return }
        let viewportSize = view.bounds.size
        guard viewportSize.width > 0, viewportSize.height > 0 else { return }
        guard viewportSize == frozen.viewportSize else {
            invalidateFrozenViewport()
            return
        }
        guard imageView.image == nil else { return }
        guard let transform = try? DepthMeasurement.viewportTransform(
            imageSize: frozen.imageSize,
            viewportSize: frozen.viewportSize,
            imageToView: frozen.imageToView
        ) else {
            invalidateFrozenViewport()
            return
        }
        UIGraphicsBeginImageContextWithOptions(frozen.viewportSize, true, 1)
        guard let context = UIGraphicsGetCurrentContext() else { UIGraphicsEndImageContext(); return }
        UIColor.black.setFill()
        context.fill(CGRect(origin: .zero, size: frozen.viewportSize))
        context.concatenate(transform)
        // UIKit image drawing uses the same top-left image coordinate convention as normalized taps.
        UIImage(cgImage: cg, scale: 1, orientation: .up).draw(in: CGRect(origin: .zero, size: frozen.imageSize))
        let rendered = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        imageView.image = rendered
    }
    private func invalidateFrozenViewport() {
        clearFrozen()
        needsRetake = true
        updateInterface()
        presentStatus("The view size changed while the frame was frozen. Press Retake to capture this view again.")
    }

    private func beginMarking() {
        guard frozen != nil else { presentStatus("Freeze a frame before marking."); return }
        switch stage {
        case .coachingFront: stage = .markingFront
        case .coachingSide: stage = .markingSide
        case .probeCoaching: stage = .probeMarking
        default: break
        }
        updateInterface()
    }

    @objc private func imageTapped(_ gesture: UITapGestureRecognizer) {
        guard stage == .markingFront || stage == .markingSide || stage == .probeMarking,
              let frozen else { return }
        guard view.bounds.size == frozen.viewportSize, imageView.bounds.size == frozen.viewportSize else {
            invalidateFrozenViewport()
            return
        }
        let point = gesture.location(in: imageView)
        do {
            let imagePoint = try DepthMeasurement.imagePoint(viewPoint: point, viewportSize: frozen.viewportSize, imageToView: frozen.imageToView)
            let depth = try DepthMeasurement.sample(imagePoint: imagePoint, depthMap: frozen.depth, confidenceMap: frozen.confidence)
            let world = try DepthMeasurement.point(imagePoint: imagePoint, depthMeters: depth, intrinsics: frozen.intrinsics, imageSize: frozen.imageSize)
            guard world.x.isFinite, world.y.isFinite, world.z.isFinite else { throw BodyScanError.invalidDepth }
            if stage == .probeMarking {
                probePoints.append(world)
                showEndpoint(at: point)
                if probePoints.count == 2 { finishProbe() }
            } else {
                pairPoints.append(world)
                showEndpoint(at: point)
                if pairPoints.count == 2 { finishPair() }
            }
            updateInterface()
        } catch {
            presentStatus("Could not measure that point (\(error.localizedDescription)). Choose a clearer point; your current step is unchanged.")
        }
    }
    private func showEndpoint(at point: CGPoint) {
        let marker = UIView(frame: CGRect(x: point.x - 9, y: point.y - 9, width: 18, height: 18))
        marker.backgroundColor = .systemYellow
        marker.layer.cornerRadius = 9
        marker.layer.borderWidth = 2
        marker.layer.borderColor = UIColor.white.cgColor
        marker.isAccessibilityElement = true
        marker.accessibilityLabel = "Marked endpoint \(endpointMarkers.count + 1)"
        markerView.addSubview(marker)
        endpointMarkers.append(marker)
    }

    private func clearEndpointMarkers() {
        endpointMarkers.forEach { $0.removeFromSuperview() }
        endpointMarkers.removeAll()
    }

    private func finishPair() {
        let spec = specs.first
        guard let spec, pairPoints.count == 2 else { return }
        let pair = MeasurementPair(first: pairPoints[0], second: pairPoints[1])
        guard pair.span.isFinite, pair.span > 0 else {
            pairPoints.removeAll()
            clearEndpointMarkers()
            presentStatus("Those endpoints did not produce a valid nonzero depth span. Tap both endpoints again.")
            return
        }
        completed[spec.key] = pair.span
        pairPoints.removeAll()
        clearFrozen()
        let isFront = stage == .markingFront
        let completedInView = isFront
            ? ["chestWidth", "waistWidth", "shoulderWidth", "torsoLength"].filter { completed[$0] != nil }.count
            : ["chestDepth", "waistDepth"].filter { completed[$0] != nil }.count
        if isFront && completedInView == 4 { stage = .coachingSide }
        else if !isFront && completedInView == 2 { stage = .review }
        else { stage = isFront ? .coachingFront : .coachingSide }
        presentStatus(stage == .coachingSide && isFront ? "Front view complete. Turn sideways, freeze a new frame, and continue." : stage == .review ? "Side view complete. Review your measurements." : "Span saved. Freeze a fresh frame for the next measurement.")
        updateInterface()
        if stage != .review { resumeSession() }
    }

    private func finishProbe() {
        guard probePoints.count == 2 else { return }
        let distance = Double(simd_distance(probePoints[0], probePoints[1]))
        guard distance.isFinite, distance > 0 else {
            probePoints.removeAll()
            clearEndpointMarkers()
            presentStatus("Invalid zero-length probe. Tap both endpoints again.")
            return
        }
        probeDistance = distance
        if let cm = Double(tapeField.text ?? ""), cm.isFinite, cm > 0 { probeError = distance - cm / 100 }
        clearFrozen()
        stage = .probeCoaching
        updateInterface()
        resumeSession()
    }
    private func startProbe() {
        guard stage == .coachingFront, completed.isEmpty else {
            presentStatus("The tape-span probe is available before the body wizard starts.")
            return
        }
        clearFrozen()
        probeDistance = nil
        probeError = nil
        stage = .probeCoaching
        updateInterface()
    }

    @objc private func tapeDistanceChanged() {
        probeError = nil
        if let distance = probeDistance, let cm = Double(tapeField.text ?? ""), cm.isFinite, cm > 0 {
            probeError = distance - cm / 100
        }
        updateInterface()
    }


    private func undo() {
        if stage == .probeMarking {
            if !probePoints.isEmpty {
                probePoints.removeLast()
                endpointMarkers.last?.removeFromSuperview()
                if !endpointMarkers.isEmpty { endpointMarkers.removeLast() }
            } else { probeDistance = nil; probeError = nil }
        } else if stage == .markingFront || stage == .markingSide {
            if !pairPoints.isEmpty {
                pairPoints.removeLast()
                endpointMarkers.last?.removeFromSuperview()
                if !endpointMarkers.isEmpty { endpointMarkers.removeLast() }
            } else { undoMostRecentSpan() }
        } else if stage == .coachingFront || stage == .coachingSide || stage == .review {
            undoMostRecentSpan()
        } else if stage == .probeCoaching, probeDistance != nil {
            probeDistance = nil
            probeError = nil
        }
        updateInterface()
    }

    private func undoMostRecentSpan() {
        let order = ["chestWidth", "waistWidth", "shoulderWidth", "torsoLength", "chestDepth", "waistDepth"]
        guard let key = order.reversed().first(where: { completed[$0] != nil }) else { return }
        completed.removeValue(forKey: key)
        stage = ["chestWidth", "waistWidth", "shoulderWidth", "torsoLength"].contains(key) ? .coachingFront : .coachingSide
        clearFrozen()
        resumeSession()
    }

    private func retake() {
        clearFrozen()
        pairPoints.removeAll()
        probePoints.removeAll()
        if stage == .probeCoaching || stage == .probeMarking {
            probeDistance = nil; probeError = nil; stage = .probeCoaching
        } else if stage == .markingFront || stage == .coachingFront {
            ["chestWidth", "waistWidth", "shoulderWidth", "torsoLength"].forEach { completed.removeValue(forKey: $0) }
            stage = .coachingFront
        } else if stage == .markingSide || stage == .coachingSide || stage == .review {
            ["chestDepth", "waistDepth"].forEach { completed.removeValue(forKey: $0) }
            stage = .coachingSide
        }
        needsRetake = false
        updateInterface()
        resumeSession()
    }

    private func continueOrUse() {
        guard !didComplete, !didCancel else { return }
        switch stage {
        case .probeCoaching where probeDistance != nil:
            probeDistance = nil
            probeError = nil
            stage = .coachingFront
            updateInterface()
        case .coachingFront, .coachingSide:
            guard frozen != nil else { presentStatus("Freeze a frame before continuing."); return }
            beginMarking()
        case .markingFront, .markingSide:
            presentStatus("Finish the current pair before continuing.")
        case .review:
            guard let profile = makeProfile() else {
                presentIssue("The scan measurements are incomplete or invalid. Retake the needed view or enter measurements manually.")
                return
            }
            didComplete = true
            stopScanning()
            onComplete?(profile)
        default:
            break
        }
    }

    private func resumeSession() {
        let configuration = ARWorldTrackingConfiguration()
        configuration.frameSemantics.insert(.sceneDepth)
        session.delegate = self
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    private func makeProfile() -> BodyProfile? {
        guard let cw = completed["chestWidth"], let cd = completed["chestDepth"],
              let ww = completed["waistWidth"], let wd = completed["waistDepth"],
              let sw = completed["shoulderWidth"], let torso = completed["torsoLength"] else { return nil }
        return try? GuidedBodyScanService().scan(BodyScanInput(chestWidth: cw, chestDepth: cd, waistWidth: ww, waistDepth: wd, shoulderWidth: sw, torsoLength: torso))
    }

    private func cancelScan() {
        guard !didCancel, !didComplete else { return }
        didCancel = true
        stopScanning()
        let callback = onCancel
        dismiss(animated: true) { callback?() }
    }

    func stopScanning() {
        clearFrozen()
        pairPoints.removeAll()
        probePoints.removeAll()
        NotificationCenter.default.removeObserver(self, name: UIApplication.didEnterBackgroundNotification, object: nil)
        session.delegate = nil
        session.pause()
    }

    private func clearFrozen() {
        frozen = nil
        renderImage = nil
        imageView.image = nil
        imageView.isHidden = true
        clearEndpointMarkers()
        pairPoints.removeAll()
        probePoints.removeAll()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isBeingDismissed || navigationController?.isBeingDismissed == true { stopScanning() }
    }

    @objc private func appDidEnterBackground() {
        handleInterruption("The app entered the background. The unfinished capture was cleared; retake the current view deliberately.")
        session.pause()
    }

    private func updateInterface() {
        guard isViewLoaded else { return }
        let isFrozen = frozen != nil
        imageView.isHidden = !isFrozen
        tapeField.isHidden = !(stage == .probeCoaching || stage == .probeMarking)
        let title: String
        switch stage {
        case .permission: title = "Allow camera access to scan, or enter measurements manually."
        case .coachingFront: title = "Front view: stand facing the camera with your upper body visible. Freeze a frame, then mark endpoints."
        case .markingFront: title = specs.first?.label ?? "Front view measurements"
        case .coachingSide: title = "Side view: turn sideways while keeping your torso visible. Freeze a new frame."
        case .markingSide: title = specs.first?.label ?? "Side view measurements"
        case .review: title = "Review your scan draft. Nothing is saved until you use it."
        case .probeCoaching: title = "Known tape-span probe: freeze a frame and mark two endpoints on a measured object."
        case .probeMarking: title = "Probe: tap the first and second ends of the known span."
        }
        statusLabel.text = title
        if stage == .review, let profile = makeProfile() {
            valueLabel.text = String(
                format: "Estimated chest: %.1f cm\nEstimated waist at navel: %.1f cm\nShoulders: %.1f cm\nTorso: %.1f cm\nReview and edit before saving.",
                profile.chestCircumference * 100, profile.waistCircumference * 100,
                profile.shoulderWidth * 100, profile.torsoLength * 100
            )
        } else if stage == .probeCoaching, let distance = probeDistance {
            let measured = String(format: "Measured: %.3f m (%.1f cm)", distance, distance * 100)
            valueLabel.text = measured + (probeError.map { "\nAbsolute tape error: \(String(format: "%.1f", abs($0) * 100)) cm (signed \(String(format: "%+.1f", $0 * 100)) cm)" } ?? "")
        } else {
            valueLabel.text = "\(completed.count) of 6 spans complete\(isFrozen ? " · frame frozen" : " · live camera") · \(pairPoints.count) endpoint(s) marked"
        }
        let enabledTitles: Set<String>
        switch stage {
        case .coachingFront: enabledTitles = isFrozen ? ["Mark", "Retake", "Continue", "Probe", "Cancel", "Undo"] : ["Freeze", "Retake", "Continue", "Probe", "Cancel", "Undo"]
        case .coachingSide: enabledTitles = isFrozen ? ["Mark", "Retake", "Continue", "Cancel", "Undo"] : ["Freeze", "Retake", "Continue", "Cancel", "Undo"]
        case .markingFront, .markingSide: enabledTitles = ["Undo", "Retake", "Cancel"]
        case .probeCoaching: enabledTitles = isFrozen ? ["Mark", "Retake", "Continue", "Cancel", "Undo"] : ["Freeze", "Retake", "Continue", "Cancel", "Undo"]
        case .probeMarking: enabledTitles = ["Undo", "Retake", "Continue", "Cancel"]
        case .review: enabledTitles = ["Undo", "Retake", "Continue", "Cancel"]
        case .permission: enabledTitles = ["Cancel"]
        }
        buttons.forEach { button in
            if button.currentTitle == "Continue" || button.currentTitle == "Use Scan" {
                let title = stage == .review ? "Use Scan" : "Continue"
                button.setTitle(title, for: .normal)
                button.accessibilityLabel = title
            }
            let title = button.currentTitle ?? ""
            button.isHidden = !enabledTitles.contains(title == "Use Scan" ? "Continue" : title)
            button.isEnabled = title != "Continue" && title != "Use Scan" || stage == .review || (stage == .probeCoaching && probeDistance != nil) || isFrozen
        }
    }

    private func presentStatus(_ message: String) { statusLabel.text = message }

    private func presentIssue(_ message: String) {
        presentStatus(message)
        updateInterface()
        let alert = UIAlertController(title: "Body Scan", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        if presentedViewController == nil { present(alert, animated: true) }
    }
}
