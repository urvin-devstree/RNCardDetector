import AVFoundation
import UIKit
import Vision

final class CardScannerViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
  var onResult: ((CardScanResult) -> Void)?
  var onCancel: (() -> Void)?
  var onError: ((Error) -> Void)?

  private let captureSession = AVCaptureSession()
  private let videoOutput = AVCaptureVideoDataOutput()
  private let videoQueue = DispatchQueue(label: "com.buddy.cards.scan.video", qos: .userInitiated)
  private var previewLayer: AVCaptureVideoPreviewLayer?

  private var textRequest: VNRecognizeTextRequest?
  private var lastProcessTime: CFTimeInterval = 0
  private let processInterval: CFTimeInterval = 0.18

  private var scanStartTime: CFTimeInterval = 0
  private var didUpgradeToAccurate = false

  private var isFinishing = false

  // Rolling consensus buffers
  private var recentPANs: [String] = []
  private var recentExpiries: [String] = []
  private var recentNames: [String] = []
  private let recentLimit = 12

  private var bestPAN: String = ""
  private var bestExpiry: String = ""
  private var bestName: String = ""
  private var bestPANCount: Int = 0
  private var bestExpiryCount: Int = 0
  private var bestNameCount: Int = 0

  private let overlayView = UIView()
  private let hintLabel = UILabel()
  private let statusLabel = UILabel()
  private let cancelButton = UIButton(type: .system)
  private let doneButton = UIButton(type: .system)
  private let torchButton = UIButton(type: .system)

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black
    setupUI()
    setupVision()
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    scanStartTime = CACurrentMediaTime()
    didUpgradeToAccurate = false
    startCameraOrFail()
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    previewLayer?.frame = view.bounds
    overlayView.frame = cardFrameRect()
    updateVisionROI()
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    stopCamera()
  }

  private func setupUI() {
    hintLabel.text = "Align your card inside the frame"
    hintLabel.textColor = .white
    hintLabel.font = .systemFont(ofSize: 15, weight: .semibold)
    hintLabel.textAlignment = .center
    hintLabel.numberOfLines = 2

    statusLabel.text = "Looking for card number…"
    statusLabel.textColor = .white
    statusLabel.font = .systemFont(ofSize: 13, weight: .regular)
    statusLabel.textAlignment = .center
    statusLabel.numberOfLines = 2

    overlayView.layer.borderColor = UIColor.white.withAlphaComponent(0.8).cgColor
    overlayView.layer.borderWidth = 2
    overlayView.layer.cornerRadius = 12
    overlayView.backgroundColor = .clear

    cancelButton.setTitle("Cancel", for: .normal)
    cancelButton.tintColor = .white
    cancelButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
    cancelButton.addTarget(self, action: #selector(handleCancel), for: .touchUpInside)

    doneButton.setTitle("Done", for: .normal)
    doneButton.tintColor = .white
    doneButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
    doneButton.isEnabled = false
    doneButton.alpha = 0.5
    doneButton.addTarget(self, action: #selector(handleDone), for: .touchUpInside)

    torchButton.setTitle("Torch", for: .normal)
    torchButton.tintColor = .white
    torchButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
    torchButton.addTarget(self, action: #selector(handleTorch), for: .touchUpInside)

    // Labels/buttons via Auto Layout. The scan frame uses manual layout for simplicity.
    [hintLabel, statusLabel, cancelButton, doneButton, torchButton].forEach {
      $0.translatesAutoresizingMaskIntoConstraints = false
      view.addSubview($0)
    }
    overlayView.translatesAutoresizingMaskIntoConstraints = true
    view.addSubview(overlayView)

    NSLayoutConstraint.activate([
      hintLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
      hintLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
      hintLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

      statusLabel.topAnchor.constraint(equalTo: hintLabel.bottomAnchor, constant: 8),
      statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
      statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

      cancelButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
      cancelButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),

      torchButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      torchButton.centerYAnchor.constraint(equalTo: cancelButton.centerYAnchor),

      doneButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
      doneButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
    ])
  }

  private func cardFrameRect() -> CGRect {
    // A credit-card-ish rectangle in portrait.
    let width = min(view.bounds.width * 0.86, 380)
    let height = width * 0.63
    let x = (view.bounds.width - width) / 2
    let y = (view.bounds.height - height) / 2
    return CGRect(x: x, y: y, width: width, height: height)
  }

  private func setupVision() {
    let request = VNRecognizeTextRequest(completionHandler: { [weak self] request, error in
      if let error = error {
        self?.handleScanError(error)
        return
      }
      guard let observations = request.results as? [VNRecognizedTextObservation] else { return }
      let lines: [String] = observations.flatMap {
        $0.topCandidates(3)
          .filter { $0.confidence >= 0.15 }
          .map { $0.string }
      }
      self?.consumeRecognizedText(lines)
    })
    // `.fast` significantly reduces latency vs `.accurate` for live scanning.
    request.recognitionLevel = .fast
    request.usesLanguageCorrection = false
    request.recognitionLanguages = ["en-US"]
    request.minimumTextHeight = 0.02
    textRequest = request
  }

  private func updateVisionROI() {
    guard let request = textRequest, let previewLayer else { return }

    // Convert the on-screen card frame into a normalized ROI for Vision.
    // `metadataOutputRectConverted` gives a normalized rect in capture coordinates (origin top-left).
    // Vision expects normalized ROI with origin bottom-left, so we flip Y.
    var metadataRect = previewLayer.metadataOutputRectConverted(fromLayerRect: overlayView.frame)

    // Expand slightly to tolerate small misalignment / perspective.
    metadataRect = metadataRect.insetBy(dx: -0.06, dy: -0.08)
    metadataRect.origin.x = max(0, metadataRect.origin.x)
    metadataRect.origin.y = max(0, metadataRect.origin.y)
    metadataRect.size.width = min(1 - metadataRect.origin.x, metadataRect.size.width)
    metadataRect.size.height = min(1 - metadataRect.origin.y, metadataRect.size.height)

    let visionROI = CGRect(
      x: metadataRect.origin.x,
      y: 1 - metadataRect.origin.y - metadataRect.size.height,
      width: metadataRect.size.width,
      height: metadataRect.size.height
    )

    // Only assign if sane; otherwise keep full-frame default.
    if visionROI.width > 0.1, visionROI.height > 0.1 {
      videoQueue.async {
        request.regionOfInterest = visionROI
      }
    }
  }

  private func startCameraOrFail() {
    if captureSession.isRunning { return }

    // If already configured (e.g. returning from an interruption), just resume.
    if !captureSession.inputs.isEmpty {
      captureSession.startRunning()
      return
    }

    let status = AVCaptureDevice.authorizationStatus(for: .video)
    switch status {
    case .authorized:
      startCameraSessionOrFail()
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
        DispatchQueue.main.async {
          guard let self else { return }
          if granted {
            self.startCameraSessionOrFail()
          } else {
            self.handleScanError(
              NSError(domain: "CardScanner", code: 1, userInfo: [NSLocalizedDescriptionKey: "Camera permission not granted"])
            )
          }
        }
      }
    default:
      handleScanError(NSError(domain: "CardScanner", code: 1, userInfo: [NSLocalizedDescriptionKey: "Camera permission not granted"]))
    }
  }

  private func startCameraSessionOrFail() {
    do {
      captureSession.beginConfiguration()
      // Prefer a lower-latency preset for OCR. `.photo` is overkill and slows processing.
      if captureSession.canSetSessionPreset(.hd1280x720) {
        captureSession.sessionPreset = .hd1280x720
      } else {
        captureSession.sessionPreset = .high
      }

      guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
        throw NSError(domain: "CardScanner", code: 2, userInfo: [NSLocalizedDescriptionKey: "No back camera available"])
      }

      // Improve OCR quality: keep focus/exposure stable.
      if device.isFocusModeSupported(.continuousAutoFocus) || device.isExposureModeSupported(.continuousAutoExposure) {
        do {
          try device.lockForConfiguration()
          if device.isFocusModeSupported(.continuousAutoFocus) {
            device.focusMode = .continuousAutoFocus
          }
          if device.isSmoothAutoFocusSupported {
            device.isSmoothAutoFocusEnabled = true
          }
          if device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
          }
          if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
            device.whiteBalanceMode = .continuousAutoWhiteBalance
          }
          if device.isLowLightBoostSupported {
            device.automaticallyEnablesLowLightBoostWhenAvailable = true
          }
          device.unlockForConfiguration()
        } catch {
          // Non-fatal; continue with defaults.
        }
      }

      let input = try AVCaptureDeviceInput(device: device)
      if captureSession.canAddInput(input) { captureSession.addInput(input) }

      // Use a cheaper pixel format for Vision than BGRA where possible.
      videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
      videoOutput.alwaysDiscardsLateVideoFrames = true
      videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
      if captureSession.canAddOutput(videoOutput) { captureSession.addOutput(videoOutput) }

      if let connection = videoOutput.connection(with: .video), connection.isVideoOrientationSupported {
        connection.videoOrientation = .portrait
      }

      captureSession.commitConfiguration()

      let layer = AVCaptureVideoPreviewLayer(session: captureSession)
      layer.videoGravity = .resizeAspectFill
      layer.frame = view.bounds
      view.layer.insertSublayer(layer, at: 0)
      previewLayer = layer

      updateVisionROI()
      torchButton.isHidden = !device.hasTorch

      captureSession.startRunning()
    } catch {
      handleScanError(error)
    }
  }

  private func stopCamera() {
    if captureSession.isRunning {
      captureSession.stopRunning()
    }
  }

  @objc private func handleCancel() {
    if isFinishing { return }
    isFinishing = true
    dismiss(animated: true) { [weak self] in
      self?.onCancel?()
    }
  }

  @objc private func handleDone() {
    // Match Android behavior: only allow finishing when expiry is present.
    guard
      !bestPAN.isEmpty,
      CardTextParser.luhnCheck(bestPAN),
      !bestExpiry.isEmpty
    else { return }
    finish()
  }

  @objc private func handleTorch() {
    guard
      let device = (captureSession.inputs.first as? AVCaptureDeviceInput)?.device,
      device.hasTorch
    else { return }

    do {
      try device.lockForConfiguration()
      device.torchMode = (device.torchMode == .on) ? .off : .on
      device.unlockForConfiguration()
    } catch {
      // Non-fatal; ignore.
    }
  }

  func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
    if isFinishing { return }
    let now = CACurrentMediaTime()
    if now - lastProcessTime < processInterval { return }
    lastProcessTime = now

    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
    guard let request = textRequest else { return }

    // If `.fast` fails to lock quickly, upgrade to `.accurate` to improve detection rates.
    // This keeps the initial experience snappy but avoids getting "stuck" on hard frames.
    if !didUpgradeToAccurate {
      let elapsed = now - scanStartTime
      let needsUpgrade = (bestPAN.isEmpty && elapsed >= 3.0) || (!bestPAN.isEmpty && bestExpiry.isEmpty && elapsed >= 2.2)
      if needsUpgrade {
        request.recognitionLevel = .accurate
        request.minimumTextHeight = 0.015
        didUpgradeToAccurate = true
      }
    }

    let orientation: CGImagePropertyOrientation = .right // Portrait + back camera
    let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
    do {
      try handler.perform([request])
    } catch {
      handleScanError(error)
    }
  }

  private func consumeRecognizedText(_ lines: [String]) {
    guard let parsed = CardTextParser.extract(from: lines) else { return }

    if !parsed.cardNumber.isEmpty {
      pushCandidate(&recentPANs, value: parsed.cardNumber)
      if let entry = consensusEntry(from: recentPANs, minCount: 2) {
        bestPAN = entry.value
        bestPANCount = entry.count
      }
    }
    if !parsed.expirationDate.isEmpty {
      pushCandidate(&recentExpiries, value: parsed.expirationDate)
      if let entry = consensusEntry(from: recentExpiries, minCount: 1) {
        bestExpiry = entry.value
        bestExpiryCount = entry.count
      }
    }
    if !parsed.cardHolderName.isEmpty {
      pushCandidate(&recentNames, value: parsed.cardHolderName)
      if let entry = consensusEntry(from: recentNames, minCount: 2) {
        bestName = entry.value
        bestNameCount = entry.count
      }
    }

    DispatchQueue.main.async { [weak self] in
      self?.updateUI()
    }

    // Auto-finish only when PAN is Luhn-valid and stable for multiple frames, plus expiry found.
    if !bestPAN.isEmpty,
       CardTextParser.luhnCheck(bestPAN),
       bestPANCount >= 2,
       !bestExpiry.isEmpty,
       bestExpiryCount >= 1 {
      finish()
    }
  }

  private func updateUI() {
    if bestPAN.isEmpty {
      statusLabel.text = "Looking for card number…"
      doneButton.isEnabled = false
      doneButton.alpha = 0.5
      return
    }

    let luhnOK = CardTextParser.luhnCheck(bestPAN)
    let redacted = CardTextParser.redact(bestPAN)
    var parts: [String] = ["Number: \(redacted)"]
    if !bestExpiry.isEmpty { parts.append("Expiry: \(bestExpiry)") }
    if !bestName.isEmpty { parts.append("Name: \(bestName)") }

    if !luhnOK {
      statusLabel.text = "Reading… hold steady (verifying number)"
    } else if bestExpiry.isEmpty {
      statusLabel.text = "Number found. Looking for expiry…"
    } else {
      statusLabel.text = parts.joined(separator: "   •   ")
    }

    let ready = luhnOK && bestPANCount >= 2 && !bestExpiry.isEmpty
    doneButton.isEnabled = ready
    doneButton.alpha = ready ? 1.0 : 0.5
  }

  private func pushCandidate(_ buffer: inout [String], value: String) {
    buffer.append(value)
    if buffer.count > recentLimit {
      buffer.removeFirst(buffer.count - recentLimit)
    }
  }

  private func consensusEntry(from buffer: [String], minCount: Int) -> (value: String, count: Int)? {
    guard !buffer.isEmpty else { return nil }
    var counts: [String: Int] = [:]
    for v in buffer { counts[v, default: 0] += 1 }
    let best = counts.max { $0.value < $1.value }
    guard let bestEntry = best, bestEntry.value >= minCount else { return nil }
    return (bestEntry.key, bestEntry.value)
  }

  private func finish() {
    if isFinishing { return }
    isFinishing = true
    stopCamera()

    let result = CardScanResult(
      cardNumber: bestPAN,
      cardNumberRedacted: CardTextParser.redact(bestPAN),
      cardHolderName: bestName,
      expirationDate: bestExpiry
    )

    DispatchQueue.main.async { [weak self] in
      self?.dismiss(animated: true) {
        self?.onResult?(result)
      }
    }
  }

  private func handleScanError(_ error: Error) {
    if isFinishing { return }
    isFinishing = true
    stopCamera()
    DispatchQueue.main.async { [weak self] in
      self?.dismiss(animated: true) {
        self?.onError?(error)
      }
    }
  }
}
