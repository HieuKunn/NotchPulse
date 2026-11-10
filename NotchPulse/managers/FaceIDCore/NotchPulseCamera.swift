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
    private let videoOutputQueue = DispatchQueue(label: "com.hieukunn.notchpulse.camera.video", qos: .userInteractive)

    /// Handed to the delegate outside the actor; only ever touched via `Task { @MainActor ... }`.
    private let framePublisher = FramePublisher()
    private var currentInput: AVCaptureDeviceInput?
    private var sessionGeneration: UInt64 = 0
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
        NSLog("[NotchPulseCamera] Recovering from runtime error: \(String(describing: error))")
        Task { @MainActor [weak self] in
            await self?.recoverStalledSession()
        }
    }

    private func handleDeviceConnected(_ device: AVCaptureDevice?) {
        NotchPulseCameraDeviceCatalog.invalidateTargetScreenCache()
        if errorMessage != nil {
            errorMessage = nil
        }
        guard isRunning else { return }
        let preferredID = NotchPulseCameraDeviceCatalog.resolvedDevice()?.uniqueID
        if currentInput == nil || (preferredID != nil && currentInput?.device.uniqueID != preferredID) {
            Task { @MainActor [weak self] in
                guard let self, self.isRunning else { return }
                let candidates = await self.waitForDevices(timeout: .milliseconds(800))
                for candidate in candidates {
                    if await self.configureAndStartSession(with: candidate) {
                        self.errorMessage = nil
                        return
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

    func start(processingFrames: Bool = true, allowAccessPrompt: Bool = true) async {
        sessionGeneration &+= 1
        let generation = sessionGeneration

        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            permission = .granted
        case .notDetermined:
            guard allowAccessPrompt else {
                permission = .notDetermined
                errorMessage = "Camera access has not been granted yet."
                return
            }
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            guard generation == sessionGeneration else { return }
            permission = granted ? .granted : .denied
        default:
            permission = .denied
        }

        guard permission == .granted else {
            let bundleID = Bundle.main.bundleIdentifier ?? "com.notchpulse.NotchPulse"
            errorMessage = "Camera access not granted (status: \(describe(status))). " +
                (status == .restricted
                    ? "macOS reports this as *restricted* — not a simple user denial. This usually means Screen Time content restrictions or an MDM/profile policy is blocking camera access for this app; toggling it in System Settings > Privacy & Security > Camera won't help until that restriction is lifted."
                    : "Enable it in System Settings > Privacy & Security > Camera. If NotchPulse isn't listed there, quit the app, run `tccutil reset Camera \(bundleID)` in Terminal, then relaunch so macOS asks again.")
            return
        }

        errorMessage = nil

        // Resilient resolution: on wake or boot, hardware daemon can take 300-1500ms to enumerate
        let devices = await waitForDevices(timeout: .milliseconds(2000))
        guard generation == sessionGeneration else { return }
        guard !devices.isEmpty else {
            errorMessage = "No camera device found."
            return
        }

        framePublisher.isProcessingFrames = processingFrames

        for device in devices {
            guard generation == sessionGeneration else { return }
            if await configureAndStartSession(with: device) {
                guard generation == sessionGeneration else {
                    sessionQueue.async { [session] in
                        if session.isRunning { session.stopRunning() }
                    }
                    return
                }
                errorMessage = nil
                isRunning = true
                return
            }
        }

        guard generation == sessionGeneration else { return }
        errorMessage = "Failed to start camera session."
        isRunning = false
    }

    func requestAccessAndStart() async {
        await start(processingFrames: true)
    }

    func stop() {
        sessionGeneration &+= 1
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
        let generation = sessionGeneration
        NSLog("[NotchPulseCamera] Stalled camera pipeline detected; attempting recovery...")
        let devices = await waitForDevices(timeout: .milliseconds(1000))
        guard isRunning, generation == sessionGeneration, !devices.isEmpty else { return }

        let stalledID = currentInput?.device.uniqueID
        let ordered = devices.sorted { ($0.uniqueID == stalledID ? 1 : 0) < ($1.uniqueID == stalledID ? 1 : 0) }
        for device in ordered {
            guard isRunning, generation == sessionGeneration else { return }
            if await configureAndStartSession(with: device, forceReconfigure: true) {
                return
            }
        }
    }

    private func waitForDevices(timeout: Duration) async -> [AVCaptureDevice] {
        let initial = NotchPulseCameraDeviceCatalog.resolvedDevices()
        if !initial.isEmpty {
            return initial
        }
        let clock = ContinuousClock()
        let start = clock.now
        while clock.now - start < timeout {
            try? await Task.sleep(for: .milliseconds(100))
            let devices = NotchPulseCameraDeviceCatalog.resolvedDevices()
            if !devices.isEmpty {
                return devices
            }
        }
        return []
    }

    private func configureAndStartSession(with device: AVCaptureDevice, forceReconfigure: Bool = false) async -> Bool {
        return await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self, session, videoOutput, videoOutputQueue, framePublisher] in
                guard let self else {
                    continuation.resume(returning: false)
                    return
                }

                if forceReconfigure && session.isRunning {
                    session.stopRunning()
                }

                session.beginConfiguration()
                session.sessionPreset = .high

                // 1. Output setup
                if !session.outputs.contains(videoOutput) {
                    videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                    videoOutput.alwaysDiscardsLateVideoFrames = true
                    videoOutput.setSampleBufferDelegate(framePublisher, queue: videoOutputQueue)
                    if session.canAddOutput(videoOutput) {
                        session.addOutput(videoOutput)
                    }
                }

                // 2. Validate existing input health (not just matching uniqueID!)
                let activeInput = session.inputs.first as? AVCaptureDeviceInput
                let isInputHealthy = !forceReconfigure
                    && activeInput != nil
                    && activeInput?.device.uniqueID == device.uniqueID
                    && NotchPulseCameraDeviceCatalog.isDeviceHealthy(activeInput?.device)

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
                    Self.selectPreferredFormat(for: device)
                    Task { @MainActor in
                        self.currentInput = input
                    }
                }

                session.commitConfiguration()

                if !session.isRunning {
                    session.startRunning()
                }
                if !session.isRunning {
                    session.beginConfiguration()
                    session.sessionPreset = .high
                    session.commitConfiguration()
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

    /// Picks the highest-resolution landscape video format (>= 15 fps) rather than square/portrait sensor modes.
    private nonisolated static func selectPreferredFormat(for device: AVCaptureDevice) {
        let candidates = device.formats.filter { format in
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let hasUsableFps = format.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= 15 }
            return dims.width >= dims.height && hasUsableFps
        }
        let best = (candidates.isEmpty ? device.formats : candidates).max { lhs, rhs in
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
            NSLog("[NotchPulseCamera] Couldn't select preferred format: \(error.localizedDescription)")
        }
    }

    fileprivate func publish(frame: CameraFrame) {
        guard isRunning, framePublisher.isProcessingFrames else { return }
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
    private final class FramePublisher: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
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
