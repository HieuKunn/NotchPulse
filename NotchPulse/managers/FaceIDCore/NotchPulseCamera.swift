@preconcurrency import AVFoundation
import AppKit
import CoreImage
import Observation

enum CameraPermission {
    case notDetermined
    case granted
    case denied
}

/// `source` is a `CIImage` — a lazy recipe, not rendered pixels — so holding onto it costs nothing until `renderCrop` uses it.
/// `pixelBuffer` allows direct hardware Vision face detection with zero conversion overhead.
/// `image` is generated lazily on-demand only when a detected face needs canonical alignment.
final class CameraFrame: @unchecked Sendable {
    let id: UInt64
    let pixelBuffer: CVPixelBuffer
    let source: CIImage
    let sourceSize: CGSize
    let workingSize: CGSize
    private var cachedCGImage: CGImage?
    private let lock = os_unfair_lock_t.allocate(capacity: 1)

    init(
        id: UInt64,
        pixelBuffer: CVPixelBuffer,
        source: CIImage,
        sourceSize: CGSize,
        workingSize: CGSize,
        image: CGImage? = nil
    ) {
        self.id = id
        self.pixelBuffer = pixelBuffer
        self.source = source
        self.sourceSize = sourceSize
        self.workingSize = workingSize
        self.cachedCGImage = image
        self.lock.initialize(to: os_unfair_lock())
    }

    deinit {
        lock.deallocate()
    }

    var image: CGImage {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        if let cached = cachedCGImage {
            return cached
        }
        let created = NotchPulseCamera.createWorkingCGImage(from: source)
        cachedCGImage = created
        return created ?? NotchPulseCamera.fallbackEmptyCGImage
    }
}

@Observable
@MainActor
final class NotchPulseCamera: NSObject {
    private(set) var permission: CameraPermission = .notDetermined
    private(set) var isRunning: Bool = false
    private(set) var currentFrame: CameraFrame?
    private(set) var errorMessage: String?

    var isProcessingFrames: Bool {
        get { framePublisher.isProcessingFrames }
        set { framePublisher.isProcessingFrames = newValue }
    }

    func pauseProcessing() {
        framePublisher.isProcessingFrames = false
        currentFrame = nil
    }

    func resumeProcessing() {
        framePublisher.isProcessingFrames = true
    }

    func clearCurrentFrame() {
        currentFrame = nil
    }

    /// True while the active device's auto-exposure is still converging — every `start()` is a cold start, and in a dim room
    /// the first ~0.5–1s of frames are underexposed enough to score below the match threshold.
    var isAdjustingExposure: Bool {
        currentInput?.device.isAdjustingExposure ?? false
    }

    /// Exposed read-only so `CameraPreviewView` can attach a preview layer to the same session.
    let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "com.hieukunn.notchpulse.camera.session")

    /// Handed to the delegate outside the actor; only ever touched via `Task { @MainActor ... }`.
    private let framePublisher = FramePublisher()
    private var currentInput: AVCaptureDeviceInput?
    private nonisolated(unsafe) var notificationTokens: [NSObjectProtocol] = []

    override init() {
        super.init()
        framePublisher.owner = self
        setupNotifications()
    }

    deinit {
        for token in notificationTokens {
            NotificationCenter.default.removeObserver(token)
        }
    }

    private func setupNotifications() {
        let nc = NotificationCenter.default
        let sessionToken = nc.addObserver(
            forName: .AVCaptureSessionRuntimeError,
            object: session,
            queue: nil
        ) { [weak self] note in
            let error = note.userInfo?[AVCaptureSessionErrorKey] as? AVError
            NSLog("[NotchPulseCamera] AVCaptureSession runtime error: \(String(describing: error))")
            Task { @MainActor [weak self] in
                self?.handleSessionRuntimeError(error)
            }
        }
        notificationTokens.append(sessionToken)

        let interruptedToken = nc.addObserver(
            forName: .AVCaptureSessionWasInterrupted,
            object: session,
            queue: nil
        ) { _ in
            NSLog("[NotchPulseCamera] AVCaptureSession was interrupted")
        }
        notificationTokens.append(interruptedToken)

        let interruptionEndedToken = nc.addObserver(
            forName: .AVCaptureSessionInterruptionEnded,
            object: session,
            queue: nil
        ) { [weak self] _ in
            NSLog("[NotchPulseCamera] AVCaptureSession interruption ended")
            Task { @MainActor [weak self] in
                guard let self, self.isRunning else { return }
                self.sessionQueue.async { [session = self.session] in
                    if !session.isRunning {
                        session.startRunning()
                    }
                }
            }
        }
        notificationTokens.append(interruptionEndedToken)

        let connectedToken = nc.addObserver(
            forName: .AVCaptureDeviceWasConnected,
            object: nil,
            queue: nil
        ) { [weak self] note in
            let device = note.object as? AVCaptureDevice
            NSLog("[NotchPulseCamera] AVCaptureDevice connected: \(device?.localizedName ?? "unknown")")
            Task { @MainActor [weak self] in
                self?.handleDeviceConnected(device)
            }
        }
        notificationTokens.append(connectedToken)

        let disconnectedToken = nc.addObserver(
            forName: .AVCaptureDeviceWasDisconnected,
            object: nil,
            queue: nil
        ) { [weak self] note in
            let device = note.object as? AVCaptureDevice
            NSLog("[NotchPulseCamera] AVCaptureDevice disconnected: \(device?.localizedName ?? "unknown")")
            Task { @MainActor [weak self] in
                self?.handleDeviceDisconnected(device)
            }
        }
        notificationTokens.append(disconnectedToken)
    }

    private func handleSessionRuntimeError(_ error: AVError?) {
        guard isRunning else { return }
        // On runtime error, invalidate current input so the next start/restart freshly recreates it
        currentInput = nil
        sessionQueue.async { [weak self, session] in
            guard let self else { return }
            if !session.isRunning {
                session.startRunning()
            }
            Task { @MainActor in
                self.isRunning = session.isRunning
            }
        }
    }

    private func handleDeviceConnected(_ device: AVCaptureDevice?) {
        NotchPulseCameraDeviceCatalog.invalidateTargetScreenCache()
        if errorMessage != nil || currentInput == nil {
            errorMessage = nil
            if isRunning {
                Task {
                    if let resolved = await self.waitForDevice(timeout: .milliseconds(800)) {
                        _ = await self.configureAndStartSession(with: resolved)
                    }
                }
            }
        }
    }

    private func handleDeviceDisconnected(_ device: AVCaptureDevice?) {
        NotchPulseCameraDeviceCatalog.invalidateTargetScreenCache()
        if let device, device.uniqueID == currentInput?.device.uniqueID {
            currentInput = nil
        }
    }

    func start(processingFrames: Bool = true) async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            permission = .granted
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            permission = granted ? .granted : .denied
        default:
            permission = .denied
        }

        guard permission == .granted else {
            errorMessage = "Camera access not granted (status: \(describe(status))). " +
                (status == .restricted
                    ? "macOS reports this as *restricted* — not a simple user denial. This usually means Screen Time content restrictions or an MDM/profile policy is blocking camera access for this app; toggling it in System Settings > Privacy & Security > Camera won't help until that restriction is lifted."
                    : "Enable it in System Settings > Privacy & Security > Camera. If NotchPulse isn't listed there, quit the app, run `tccutil reset Camera com.hieukunn.notchpulse` in Terminal, then relaunch so macOS asks again.")
            return
        }

        errorMessage = nil

        // Resilient resolution: on wake or boot, hardware daemon can take 300-1500ms to enumerate
        guard let device = await waitForDevice(timeout: .milliseconds(2000)) else {
            errorMessage = "No camera device found."
            return
        }

        framePublisher.isProcessingFrames = processingFrames

        let success = await configureAndStartSession(with: device)
        if !success {
            errorMessage = "Failed to start camera session."
            isRunning = false
            return
        }

        isRunning = true
    }

    func requestAccessAndStart() async {
        await start(processingFrames: true)
    }

    func stop() {
        framePublisher.isProcessingFrames = false
        sessionQueue.async { [session] in
            if session.isRunning {
                session.stopRunning()
            }
        }
        isRunning = false
        currentFrame = nil
    }

    /// Attempts to recover a running session that has stopped producing frames.
    func recoverStalledSession() async {
        guard isRunning else { return }
        NSLog("[NotchPulseCamera] Stalled camera pipeline detected; attempting recovery...")
        guard let device = await waitForDevice(timeout: .milliseconds(1000)) else { return }
        _ = await configureAndStartSession(with: device)
    }

    private func waitForDevice(timeout: Duration) async -> AVCaptureDevice? {
        if let device = NotchPulseCameraDeviceCatalog.resolvedDevice() {
            return device
        }
        let clock = ContinuousClock()
        let start = clock.now
        while clock.now - start < timeout {
            try? await Task.sleep(for: .milliseconds(100))
            if let device = NotchPulseCameraDeviceCatalog.resolvedDevice() {
                return device
            }
        }
        return nil
    }

    private func configureAndStartSession(with device: AVCaptureDevice) async -> Bool {
        return await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self, session, videoOutput, framePublisher] in
                guard let self else {
                    continuation.resume(returning: false)
                    return
                }

                session.beginConfiguration()
                session.sessionPreset = .high

                // 1. Output setup
                if !session.outputs.contains(videoOutput) {
                    videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                    videoOutput.alwaysDiscardsLateVideoFrames = true
                    videoOutput.setSampleBufferDelegate(framePublisher, queue: self.sessionQueue)
                    if session.canAddOutput(videoOutput) {
                        session.addOutput(videoOutput)
                    }
                }

                // 2. Validate existing input health (not just matching uniqueID!)
                var isInputHealthy = false
                let activeInput = session.inputs.first as? AVCaptureDeviceInput
                if let activeInput,
                   activeInput.device.uniqueID == device.uniqueID,
                   NotchPulseCameraDeviceCatalog.isDeviceHealthy(activeInput.device) {
                    isInputHealthy = true
                }

                if !isInputHealthy {
                    for input in session.inputs {
                        session.removeInput(input)
                    }

                    // Retry up to 3 times (100ms apart) in case CoreMediaIO bus handshake is still in progress
                    var createdInput: AVCaptureDeviceInput?
                    for attempt in 1...3 {
                        if let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) {
                            createdInput = input
                            break
                        }
                        if attempt < 3 {
                            Thread.sleep(forTimeInterval: 0.1)
                        }
                    }

                    guard let input = createdInput else {
                        session.commitConfiguration()
                        Task { @MainActor in
                            self.currentInput = nil
                            self.errorMessage = "Failed to connect to camera device."
                        }
                        continuation.resume(returning: false)
                        return
                    }

                    session.addInput(input)
                    Self.selectHighestResolutionFormat(for: device)
                    Task { @MainActor in
                        self.currentInput = input
                    }
                }

                session.commitConfiguration()

                if !session.isRunning {
                    session.startRunning()
                }

                let running = session.isRunning
                continuation.resume(returning: running)
            }
        }
    }

    private func describe(_ status: AVAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "notDetermined"
        case .restricted: return "restricted"
        case .denied: return "denied"
        case .authorized: return "authorized"
        @unknown default: return "unknown(\(status.rawValue))"
        }
    }

    /// Highest resolution regardless of fps — Vision still works from the downscaled frame; this only affects
    /// what `CameraFrame.source` (and therefore `renderCrop`) has to work with.
    private nonisolated static func selectHighestResolutionFormat(for device: AVCaptureDevice) {
        let best = device.formats.max { lhs, rhs in
            let l = CMVideoFormatDescriptionGetDimensions(lhs.formatDescription)
            let r = CMVideoFormatDescriptionGetDimensions(rhs.formatDescription)
            return Int(l.width) * Int(l.height) < Int(r.width) * Int(r.height)
        }
        guard let best else { return }
        do {
            try device.lockForConfiguration()
            device.activeFormat = best
            device.unlockForConfiguration()
        } catch {
            NSLog("[NotchPulseCamera] Couldn't select highest-resolution format: \(error.localizedDescription)")
        }
    }

    fileprivate func publish(frame: CameraFrame) {
        currentFrame = frame
    }

    private nonisolated static let workingImageCIContext = CIContext(options: [.useSoftwareRenderer: false])
    nonisolated static let maxWorkingEdge: CGFloat = 640

    nonisolated static func createWorkingCGImage(from sourceImage: CIImage) -> CGImage? {
        var ciImage = sourceImage
        let longEdge = max(ciImage.extent.width, ciImage.extent.height)
        if longEdge > maxWorkingEdge {
            let scale = maxWorkingEdge / longEdge
            ciImage = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        return workingImageCIContext.createCGImage(ciImage, from: ciImage.extent)
    }

    nonisolated static let fallbackEmptyCGImage: CGImage = {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return context.makeImage()!
    }()

    /// Renders a native-resolution crop of `imageRect` from `frame.source`, for spoof-cue extraction which
    /// needs pixel detail (screen texture, moiré, gloss) the downscaled working frame throws away.
    nonisolated static func renderCrop(from frame: CameraFrame, imageRect: CGRect, maxEdge: CGFloat = 448) -> CGImage? {
        let workingWidth = CGFloat(frame.image.width)
        let workingHeight = CGFloat(frame.image.height)
        guard workingWidth > 0, workingHeight > 0 else { return nil }
        let scaleX = frame.sourceSize.width / workingWidth
        let scaleY = frame.sourceSize.height / workingHeight

        // Expand ~1.3x so device edges/bezels are captured for texture/moiré cues.
        let expanded = imageRect.insetBy(dx: -imageRect.width * 0.15, dy: -imageRect.height * 0.15)

        // Flip from `imageRect`'s top-left/y-down space to Core Image's bottom-left/y-up (reverse of NotchPulseFaceDetector.convertToImageSpace).
        let nativeX = expanded.origin.x * scaleX
        let nativeWidth = expanded.width * scaleX
        let nativeHeight = expanded.height * scaleY
        let nativeY = frame.sourceSize.height - (expanded.origin.y + expanded.height) * scaleY
        var nativeRect = CGRect(x: nativeX, y: nativeY, width: nativeWidth, height: nativeHeight)

        let sourceExtent = CGRect(origin: .zero, size: frame.sourceSize)
        nativeRect = nativeRect.intersection(sourceExtent)
        guard !nativeRect.isEmpty else { return nil }

        var cropped = frame.source.cropped(to: nativeRect)
            .transformed(by: CGAffineTransform(translationX: -nativeRect.minX, y: -nativeRect.minY))
        let longEdge = max(nativeRect.width, nativeRect.height)
        if longEdge > maxEdge {
            let scale = maxEdge / longEdge
            cropped = cropped.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }

        return cropRenderContext.createCGImage(cropped, from: cropped.extent)
    }

    /// `CIContext` is expensive to create and safe to reuse concurrently. Explicitly `nonisolated` since a `static let`
    /// on this `@MainActor` class would otherwise be main-actor-isolated, which the `nonisolated renderCrop` can't touch.
    private nonisolated static let cropRenderContext = CIContext()

    /// Sample-buffer callbacks arrive on `sessionQueue`, off the main actor; this delegate converts there, then hops back.
    private final class FramePublisher: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
        weak var owner: NotchPulseCamera?
        private var _isProcessingFrames: Bool = false
        private let lock = os_unfair_lock_t.allocate(capacity: 1)
        private var nextFrameID: UInt64 = 0

        override init() {
            super.init()
            lock.initialize(to: os_unfair_lock())
        }

        deinit {
            lock.deallocate()
        }

        var isProcessingFrames: Bool {
            get {
                os_unfair_lock_lock(lock)
                defer { os_unfair_lock_unlock(lock) }
                return _isProcessingFrames
            }
            set {
                os_unfair_lock_lock(lock)
                _isProcessingFrames = newValue
                os_unfair_lock_unlock(lock)
            }
        }

        func captureOutput(
            _ output: AVCaptureOutput,
            didOutput sampleBuffer: CMSampleBuffer,
            from connection: AVCaptureConnection
        ) {
            guard isProcessingFrames else { return }

            autoreleasepool {
                guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
                let sourceImage = CIImage(cvPixelBuffer: pixelBuffer)
                let sourceExtent = sourceImage.extent

                let longEdge = max(sourceExtent.width, sourceExtent.height)
                let scale = longEdge > NotchPulseCamera.maxWorkingEdge ? (NotchPulseCamera.maxWorkingEdge / longEdge) : 1.0
                let workingSize = CGSize(width: round(sourceExtent.width * scale), height: round(sourceExtent.height * scale))

                nextFrameID &+= 1
                let frame = CameraFrame(
                    id: nextFrameID,
                    pixelBuffer: pixelBuffer,
                    source: sourceImage,
                    sourceSize: sourceExtent.size,
                    workingSize: workingSize
                )

                Task { @MainActor [weak owner] in
                    owner?.publish(frame: frame)
                }
            }
        }
    }
}
