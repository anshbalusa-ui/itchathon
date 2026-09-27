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
        let cameraImageSize: CGSize
        let imageSize: CGSize
        let viewportSize: CGSize
        let imageToView: CGAffineTransform
        let orientedToCamera: CGAffineTransform
        let interfaceOrientation: UIInterfaceOrientation
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
    private let instructionTitleLabel = UILabel()
    private let instructionDetailLabel = UILabel()
    private let statusLabel = UILabel()
    private let progressLabel = UILabel()
    private let progressView = UIProgressView(progressViewStyle: .default)
    private let valueLabel = UILabel()
    private let tapeField = UITextField()
    private var buttons: [String: UIButton] = [:]
    private var endpointMarkers: [UIView] = []
    private let frontSpans: [(key: String, label: String)] = [
        ("chestWidth", "Chest width — widest point across chest"),
        ("waistWidth", "Waist width — level with navel"),
        ("shoulderWidth", "Shoulder width — outer shoulder to outer shoulder"),
        ("torsoLength", "Torso length — suprasternal notch to navel")
    ]
    private let sideSpans: [(key: String, label: String)] = [
        ("chestDepth", "Chest depth — side view"),
        ("waistDepth", "Waist depth — level with navel")
    ]
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
    private var preserveCompletedOnRetake = false
    private var issueMessage: String?
    private var interruptionMessage: String?
    private var pendingIssueAlert: UIAlertController?
    private var didComplete = false
    private var didRequestPermission = false

    private var specs: [(key: String, label: String)] {
        let all = stage == .markingFront || stage == .coachingFront ? frontSpans : sideSpans
        return all.filter { completed[$0.key] == nil }
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .all }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        session.delegate = self
        configureViews()
        NotificationCenter.default.addObserver(self, selector: #selector(appDidEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        presentPendingIssueAlert()
        guard !didRequestPermission else { return }
        didRequestPermission = true
        checkPermissionAndStart()
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateFrozenRendering()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        if frozen != nil { invalidateFrozenViewport() }
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

        let instructionCard = UIVisualEffectView(effect: UIBlurEffect(style: .regular))
        instructionCard.translatesAutoresizingMaskIntoConstraints = false
        instructionCard.layer.cornerRadius = 16
        instructionCard.layer.cornerCurve = .continuous
        instructionCard.clipsToBounds = true
        instructionCard.isUserInteractionEnabled = false
        view.addSubview(instructionCard)
        let instructionStack = UIStackView(arrangedSubviews: [instructionTitleLabel, instructionDetailLabel])
        instructionStack.axis = .vertical
        instructionStack.spacing = 4
        instructionStack.alignment = .center
        instructionStack.translatesAutoresizingMaskIntoConstraints = false
        instructionCard.contentView.addSubview(instructionStack)
        NSLayoutConstraint.activate([
            instructionCard.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            instructionCard.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            instructionCard.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            instructionStack.leadingAnchor.constraint(equalTo: instructionCard.contentView.leadingAnchor, constant: 14),
            instructionStack.trailingAnchor.constraint(equalTo: instructionCard.contentView.trailingAnchor, constant: -14),
            instructionStack.topAnchor.constraint(equalTo: instructionCard.contentView.topAnchor, constant: 10),
            instructionStack.bottomAnchor.constraint(equalTo: instructionCard.contentView.bottomAnchor, constant: -10)
        ])
        instructionTitleLabel.font = .preferredFont(forTextStyle: .headline)
        instructionTitleLabel.adjustsFontForContentSizeCategory = true
        instructionTitleLabel.textColor = .label
        instructionTitleLabel.textAlignment = .center
        instructionTitleLabel.numberOfLines = 0
        instructionDetailLabel.font = .preferredFont(forTextStyle: .footnote)
        instructionDetailLabel.adjustsFontForContentSizeCategory = true
        instructionDetailLabel.textColor = .secondaryLabel
        instructionDetailLabel.textAlignment = .center
        instructionDetailLabel.numberOfLines = 0

        let panel = UIVisualEffectView(effect: UIBlurEffect(style: .regular))
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.layer.cornerRadius = 22
        panel.layer.cornerCurve = .continuous
        panel.clipsToBounds = true
        view.addSubview(panel)
        NSLayoutConstraint.activate([
            panel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            panel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            panel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            panel.topAnchor.constraint(greaterThanOrEqualTo: instructionCard.bottomAnchor, constant: 12)
        ])

        let content = UIStackView()
        content.axis = .vertical
        content.spacing = 6
        content.alignment = .fill
        content.isLayoutMarginsRelativeArrangement = true
        content.layoutMargins = UIEdgeInsets(top: 9, left: 15, bottom: 9, right: 15)
        content.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: panel.contentView.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: panel.contentView.trailingAnchor),
            content.topAnchor.constraint(equalTo: panel.contentView.topAnchor),
            content.bottomAnchor.constraint(equalTo: panel.contentView.bottomAnchor)
        ])

        statusLabel.font = .preferredFont(forTextStyle: .footnote)
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 2
        content.addArrangedSubview(statusLabel)
        progressLabel.font = .preferredFont(forTextStyle: .caption1)
        progressLabel.adjustsFontForContentSizeCategory = true
        progressLabel.textColor = .secondaryLabel
        progressLabel.numberOfLines = 1
        progressLabel.accessibilityLabel = "Current body scan step"
        content.addArrangedSubview(progressLabel)
        progressView.progressTintColor = .systemBlue
        progressView.trackTintColor = UIColor.label.withAlphaComponent(0.15)
        progressView.accessibilityLabel = "Body scan progress"
        progressView.isAccessibilityElement = true
        content.addArrangedSubview(progressView)
        valueLabel.numberOfLines = 1
        valueLabel.font = .preferredFont(forTextStyle: .footnote)
        valueLabel.adjustsFontForContentSizeCategory = true
        valueLabel.textColor = .secondaryLabel
        valueLabel.accessibilityLabel = "Latest measured value"
        content.addArrangedSubview(valueLabel)

        tapeField.placeholder = "Optional tape distance (cm)"
        tapeField.accessibilityLabel = "Known tape distance in centimeters"
        tapeField.keyboardType = .decimalPad
        tapeField.textColor = .label
        tapeField.backgroundColor = UIColor.label.withAlphaComponent(0.06)
        tapeField.layer.cornerRadius = 8
        tapeField.isHidden = true
        tapeField.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        content.addArrangedSubview(tapeField)
        tapeField.addTarget(self, action: #selector(tapeDistanceChanged), for: .editingChanged)

        let primaryRow = UIStackView()
        primaryRow.axis = .horizontal
        primaryRow.spacing = 8
        primaryRow.distribution = .fillEqually
        content.addArrangedSubview(primaryRow)
        let secondaryRow = UIStackView()
        secondaryRow.axis = .horizontal
        secondaryRow.spacing = 8
        secondaryRow.distribution = .fillEqually
        content.addArrangedSubview(secondaryRow)
        func addButton(_ title: String, to row: UIStackView, primary: Bool) {
            let button = UIButton(type: .system)
            button.setTitle(title, for: .normal)
            button.accessibilityLabel = title == "Mark" ? "Mark two endpoints" : title
            button.accessibilityHint = title == "Mark" ? "Then tap the two endpoints on the frozen image." : nil
            button.titleLabel?.font = .preferredFont(forTextStyle: .body)
            button.titleLabel?.adjustsFontForContentSizeCategory = true
            button.titleLabel?.numberOfLines = 0
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
            button.layer.cornerRadius = 11
            button.layer.cornerCurve = .continuous
            button.backgroundColor = primary ? UIColor.systemBlue : UIColor.secondarySystemBackground.withAlphaComponent(0.9)
            button.setTitleColor(primary ? .white : .label, for: .normal)
            button.addTarget(self, action: #selector(controlTapped(_:)), for: .touchUpInside)
            row.addArrangedSubview(button)
            buttons[title] = button
        }
        addButton("Freeze", to: primaryRow, primary: true)
        addButton("Mark", to: primaryRow, primary: true)
        addButton("Continue", to: primaryRow, primary: true)
        addButton("Undo", to: secondaryRow, primary: false)
        addButton("Retake", to: secondaryRow, primary: false)
        addButton("Probe", to: secondaryRow, primary: false)
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
        case .denied:
            presentIssue("Camera access was denied. Allow access in Settings or enter measurements manually.")
        case .restricted:
            presentIssue("Camera access is restricted. Enter measurements manually.")
        @unknown default:
            presentIssue("Camera access is unavailable. Enter measurements manually.")
        }
    }

    private func startSession() {
        guard UIApplication.shared.applicationState != .background else { return }
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
        preserveCompletedOnRetake = false
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
        interruptionMessage = message
        updateInterface()
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
        guard let interfaceOrientation = view.window?.windowScene?.interfaceOrientation,
              let imageOrientation = Self.imageOrientation(for: interfaceOrientation),
              let rawToOriented = Self.rawToOrientedImageTransform(for: imageOrientation),
              let stillImage = makeImage(from: frame.capturedImage, orientation: imageOrientation) else {
            presentStatus("The screen orientation or frozen camera image is not ready. Try again.")
            return
        }
        let cameraToView = frame.displayTransform(for: interfaceOrientation, viewportSize: viewportSize)
        guard let imageToView = Self.orientedImageToViewTransform(cameraToView: cameraToView,
                                                                  imageOrientation: imageOrientation) else {
            presentStatus("The camera view transform is invalid. Try freezing again.")
            return
        }
        let cameraImageSize = CGSize(width: CVPixelBufferGetWidth(frame.capturedImage),
                                     height: CVPixelBufferGetHeight(frame.capturedImage))
        frozen = FrozenBodyFrame(image: frame.capturedImage, depth: depthData.depthMap, confidence: confidence,
                                 intrinsics: frame.camera.intrinsics, cameraImageSize: cameraImageSize,
                                 imageSize: stillImage.size, viewportSize: viewportSize, imageToView: imageToView,
                                 orientedToCamera: rawToOriented.inverted(), interfaceOrientation: interfaceOrientation)
        session.pause()
        pairPoints.removeAll()
        probePoints.removeAll()
        renderImage = stillImage
        imageView.isHidden = false
        updateFrozenRendering()
        updateInterface()
        presentStatus("Frame frozen. Tap Mark, then tap the two visible endpoints.")
    }

    private func makeImage(from buffer: CVPixelBuffer, orientation: UIImage.Orientation) -> UIImage? {
        let image = CIImage(cvPixelBuffer: buffer)
        guard let cg = imageContext.createCGImage(image, from: image.extent) else { return nil }
        return UIImage(cgImage: cg, scale: 1, orientation: orientation)
    }

    static func imageOrientation(for interfaceOrientation: UIInterfaceOrientation) -> UIImage.Orientation? {
        switch interfaceOrientation {
        case .portrait: return .right
        case .portraitUpsideDown: return .left
        case .landscapeLeft: return .up
        case .landscapeRight: return .down
        default: return nil
        }
    }

    static func rawToOrientedImageTransform(for orientation: UIImage.Orientation) -> CGAffineTransform? {
        switch orientation {
        case .up: return .identity
        case .right: return CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1, ty: 0)
        case .down: return CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: 1, ty: 1)
        case .left: return CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: 1)
        default: return nil
        }
    }

    static func orientedImageToViewTransform(
        cameraToView: CGAffineTransform,
        imageOrientation: UIImage.Orientation
    ) -> CGAffineTransform? {
        guard let rawToOriented = rawToOrientedImageTransform(for: imageOrientation) else { return nil }
        return rawToOriented.inverted().concatenating(cameraToView)
    }

    private func updateFrozenRendering() {
        guard let frozen, let image = renderImage else { return }
        let viewportSize = view.bounds.size
        guard viewportSize.width > 0, viewportSize.height > 0 else { return }
        guard viewportSize == frozen.viewportSize,
              view.window?.windowScene?.interfaceOrientation == frozen.interfaceOrientation else {
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
        image.draw(in: CGRect(origin: .zero, size: frozen.imageSize))
        let rendered = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        imageView.image = rendered
    }

    private func invalidateFrozenViewport() {
        guard frozen != nil else { return }
        preserveCompletedOnRetake = true
        clearFrozen()
        needsRetake = true
        updateInterface()
        presentStatus("The view rotated or resized. Press Retake to clear pending endpoints, then freeze again. Completed spans were kept.")
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
        guard view.bounds.size == frozen.viewportSize, imageView.bounds.size == frozen.viewportSize,
              view.window?.windowScene?.interfaceOrientation == frozen.interfaceOrientation else {
            invalidateFrozenViewport()
            return
        }
        let point = gesture.location(in: imageView)
        do {
            let orientedPoint = try DepthMeasurement.imagePoint(viewPoint: point, viewportSize: frozen.viewportSize, imageToView: frozen.imageToView)
            let cameraPoint = orientedPoint.applying(frozen.orientedToCamera)
            let depth = try DepthMeasurement.sample(imagePoint: cameraPoint, depthMap: frozen.depth, confidenceMap: frozen.confidence)
            let world = try DepthMeasurement.point(imagePoint: cameraPoint, depthMeters: depth, intrinsics: frozen.intrinsics, imageSize: frozen.cameraImageSize)
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
        if preserveCompletedOnRetake {
            preserveCompletedOnRetake = false
            if stage == .markingFront { stage = .coachingFront }
            else if stage == .markingSide { stage = .coachingSide }
            else if stage == .probeMarking { stage = .probeCoaching }
        } else if stage == .probeCoaching || stage == .probeMarking {
            probeDistance = nil; probeError = nil; stage = .probeCoaching
        } else if stage == .markingFront || stage == .coachingFront {
            ["chestWidth", "waistWidth", "shoulderWidth", "torsoLength"].forEach { completed.removeValue(forKey: $0) }
            stage = .coachingFront
        } else if stage == .markingSide || stage == .coachingSide || stage == .review {
            ["chestDepth", "waistDepth"].forEach { completed.removeValue(forKey: $0) }
            stage = .coachingSide
        }
        interruptionMessage = nil
        needsRetake = false
        updateInterface()
        resumeSession()
    }

    private func continueOrUse() {
        guard !didComplete else { return }
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
        guard UIApplication.shared.applicationState != .background else { return }
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
        tapeField.isHidden = stage != .probeCoaching && stage != .probeMarking

        let isFront = stage == .coachingFront || stage == .markingFront
        let currentSpans = isFront ? frontSpans : sideSpans
        let currentSpan = currentSpans.first { completed[$0.key] == nil }
        let frontCount = frontSpans.filter { completed[$0.key] != nil }.count
        let sideCount = sideSpans.filter { completed[$0.key] != nil }.count
        let totalCount = frontCount + sideCount

        switch stage {
        case .permission:
            instructionTitleLabel.text = "Body scan"
            instructionDetailLabel.text = "Enable camera access to begin, or use manual entry."
        case .coachingFront, .markingFront:
            instructionTitleLabel.text = currentSpan?.label.components(separatedBy: " — ").first ?? "Front view"
            let number = frontCount + 1
            let action = stage == .markingFront ? "Tap two visible endpoints on the frozen image." : "Face the camera with your upper body visible."
            instructionDetailLabel.text = "Front view · Span \(number) of 4\n\(action)"
        case .coachingSide, .markingSide:
            instructionTitleLabel.text = currentSpan?.label.components(separatedBy: " — ").first ?? "Side view"
            let number = sideCount + 1
            let action = stage == .markingSide ? "Tap two visible endpoints on the frozen image." : "Turn sideways and keep your torso visible."
            instructionDetailLabel.text = "Side view · Span \(number) of 2\n\(action)"
        case .review:
            instructionTitleLabel.text = "Review body scan"
            instructionDetailLabel.text = "All six spans captured. Nothing is saved until you choose Use Scan."
        case .probeCoaching:
            instructionTitleLabel.text = "Optional depth probe"
            instructionDetailLabel.text = probeDistance == nil
                ? "Freeze a known tape span and mark both endpoints."
                : "Probe complete · Continue to the body scan."
        case .probeMarking:
            instructionTitleLabel.text = "Mark reference span"
            instructionDetailLabel.text = "Tap the two ends of the known span on the frozen image."
        }

        switch stage {
        case .permission:
            statusLabel.text = issueMessage ?? "Camera and scene depth are required for a scan."
        case .coachingFront:
            statusLabel.text = interruptionMessage ?? (isFrozen ? "Frame frozen · Mark two endpoints." : "Live camera · Freeze a clear front frame.")
        case .markingFront:
            statusLabel.text = interruptionMessage ?? (pairPoints.isEmpty ? "Tap the first endpoint." : "Tap the second endpoint.")
        case .coachingSide:
            statusLabel.text = interruptionMessage ?? (isFrozen ? "Frame frozen · Mark two endpoints." : "Live camera · Freeze a clear side frame.")
        case .markingSide:
            statusLabel.text = interruptionMessage ?? (pairPoints.isEmpty ? "Tap the first endpoint." : "Tap the second endpoint.")
        case .review:
            statusLabel.text = "Scan draft ready · Review measurements before using scan."
        case .probeCoaching:
            statusLabel.text = isFrozen ? "Frame frozen · Mark the known span." : "Optional calibration · Does not change body measurements."
        case .probeMarking:
            statusLabel.text = probePoints.isEmpty ? "Tap the first end of the known span." : "Tap the second end of the known span."
        }

        if stage == .permission, let issueMessage { statusLabel.text = issueMessage }
        if let interruptionMessage,
           stage == .coachingFront || stage == .markingFront || stage == .coachingSide || stage == .markingSide {
            statusLabel.text = interruptionMessage
        }

        let currentDimension: String
        switch stage {
        case .coachingFront, .markingFront:
            currentDimension = currentSpan?.label.components(separatedBy: " — ").first ?? "Front view"
        case .coachingSide, .markingSide:
            currentDimension = currentSpan?.label.components(separatedBy: " — ").first ?? "Side view"
        case .probeCoaching, .probeMarking:
            currentDimension = "Depth probe"
        case .review:
            currentDimension = "Review"
        case .permission:
            currentDimension = "Body scan"
        }
        progressLabel.text = "\(currentDimension) · \(totalCount) of 6 spans"
        progressLabel.accessibilityValue = "\(currentDimension), \(totalCount) of 6 spans complete"
        progressView.progress = Float(totalCount) / 6
        progressView.accessibilityValue = "\(totalCount) of 6 spans complete"

        if stage == .probeCoaching, let probeDistance {
            valueLabel.text = probeError.map {
                String(format: "Probe: %.1f cm · Tape difference: %+.1f cm", probeDistance * 100, $0 * 100)
            } ?? String(format: "Probe: %.1f cm", probeDistance * 100)
        } else if let latest = sideSpans.reversed().first(where: { completed[$0.key] != nil })
                    ?? frontSpans.reversed().first(where: { completed[$0.key] != nil }),
                  let centimeters = completed[latest.key] {
            let name = latest.label.components(separatedBy: " — ").first ?? latest.label
            valueLabel.text = String(format: "Latest: %@ %.1f cm", name, centimeters * 100)
        } else {
            valueLabel.text = "Latest: —"
        }
        valueLabel.accessibilityValue = valueLabel.text

        let canUndo: Bool
        switch stage {
        case .probeCoaching: canUndo = probeDistance != nil
        case .probeMarking: canUndo = !probePoints.isEmpty
        case .coachingFront, .markingFront, .coachingSide, .markingSide, .review:
            canUndo = !pairPoints.isEmpty || !completed.isEmpty
        case .permission: canUndo = false
        }
        var visible: Set<String> = []
        switch stage {
        case .coachingFront:
            visible.insert(isFrozen ? "Mark" : "Freeze")
            visible.formUnion(["Undo", "Retake"])
            if completed.isEmpty { visible.insert("Probe") }
        case .coachingSide:
            visible.insert(isFrozen ? "Mark" : "Freeze")
            visible.formUnion(["Undo", "Retake"])
        case .markingFront, .markingSide:
            visible.formUnion(["Undo", "Retake"])
        case .probeCoaching:
            if probeDistance == nil {
                visible.insert(isFrozen ? "Mark" : "Freeze")
            } else {
                visible.insert("Continue")
            }
            visible.formUnion(["Undo", "Retake"])
        case .probeMarking:
            visible.formUnion(["Undo", "Retake"])
        case .review:
            visible.formUnion(["Continue", "Undo", "Retake"])
        case .permission:
            break
        }
        buttons.forEach { key, button in
            let title = key == "Continue" && stage == .review ? "Use Scan" : key
            button.setTitle(title, for: .normal)
            button.accessibilityLabel = key == "Mark" ? "Mark two endpoints" : key == "Freeze" ? "Freeze camera frame" : title
            button.accessibilityHint = key == "Mark" ? "Tap the two endpoints on the frozen image." : nil
            button.isHidden = !visible.contains(key)
            button.isEnabled = key != "Undo" || canUndo
            if key == "Freeze" { button.isEnabled = !needsRetake }
            if key == "Mark" { button.isEnabled = isFrozen }
            if key == "Continue" { button.isEnabled = stage == .review || (stage == .probeCoaching && probeDistance != nil) }
        }
    }

    private func presentStatus(_ message: String) { statusLabel.text = message }

    private func presentIssue(_ message: String) {
        if stage == .permission { issueMessage = message }
        updateInterface()
        let alert = UIAlertController(title: "Body Scan", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Enter Manually", style: .default) { [weak self] _ in
            self?.onCancel?()
        })
        pendingIssueAlert = alert
        presentPendingIssueAlert()
    }

    private func presentPendingIssueAlert() {
        guard view.window != nil, presentedViewController == nil,
              let alert = pendingIssueAlert else { return }
        pendingIssueAlert = nil
        present(alert, animated: true)
    }
}
