import AppKit
import SwiftUI
import Observation

@Observable
@MainActor
final class FaceIDOverlayController {
    /// One overlay window for the whole app — sharing one instance guarantees
    /// the triggers never run concurrently, rather than leaving that incidental.
    static let shared = FaceIDOverlayController()

    enum Phase: Equatable {
        /// While armed, the window stays on-screen here (hover-reactive); otherwise ordered out.
        case closed
        /// Expanded, showing the idle still image — actively looking for a face.
        case scanning
        /// Success animation playing, then auto-collapses.
        case success
        /// Failure animation playing/held; collapses after a hold unless
        /// the user hovers first to retry.
        case failure
        case collapsing
        /// Hosting the multi-step onboarding flow, driven by the hosted
        /// FaceIDEnrollmentController rather than this controller's own machinery.
        case onboarding
    }

    /// Kept as one enum (rather than two independent optionals) so exactly one is ever active.
    enum Content: Equatable {
        case scan(FaceIDScanMedia)
        case onboarding(FaceIDEnrollmentController)

        static func == (lhs: Content, rhs: Content) -> Bool {
            switch (lhs, rhs) {
            case (.scan(let a), .scan(let b)): return a == b
            case (.onboarding(let a), .onboarding(let b)): return a === b
            default: return false
            }
        }
    }

    private(set) var phase: Phase = .closed {
        didSet {
            if phase != oldValue {
                NotificationCenter.default.post(name: Notification.Name.faceIDPhaseChanged, object: nil)
            }
        }
    }
    private(set) var content: Content = .scan(.idle)
    /// Read-only convenience for the scan-mode view/callers — `.idle` while
    /// onboarding owns the panel.
    var media: FaceIDScanMedia {
        if case .scan(let media) = content { return media }
        return .idle
    }
    private(set) var geometry: FaceIDOverlayGeometry = .forMainScreen()
    /// Read by the view for the hover-driven size/shadow bump — irrelevant
    /// to the phase state machine itself.
    private(set) var isArmed = false
    private(set) var isPresenting = false

    var isSessionActive: Bool {
        (isArmed && NotchPulseLockMonitor.isScreenActuallyLocked()) || isPresenting || phase != .closed
    }

    @MainActor
    static var isOnboardingActive: Bool = false

    var isOnboardingActive: Bool {
        Self.isOnboardingActive
    }

    /// Pill style only: whether the pill is parked on screen at rest vs. off-screen.
    /// Deliberately separate from `isArmed` — it lags it by a frame on the way in
    /// (making the pill slide into place) and leads it on the way out.
    private(set) var isPillDocked = false

    /// Snapshotted from `NotchPulseFaceIDSettings` when a cycle begins rather than read live,
    /// so a settings change mid-attempt can't resize the panel or change how it resolves.
    private(set) var activeUnlockStyle: UnlockAnimationStyle = .original

    /// What a hover-driven activation should do — set by `arm()` (persists
    /// across scan cycles) or by one-shot `present(onRetry:)` (single use).
    private var onActivate: (() -> Void)?

    private let windowController = FaceIDOverlayWindowController()
    private var resolveTask: Task<Void, Never>?
    private var scanTimeoutTask: Task<Void, Never>?
    private var searchingAnimationTask: Task<Void, Never>?

    /// Guards `primeWindowIfNeeded` so the extra render pass only happens on the first show.
    private var hasPrimedWindow = false

    /// Matches the success asset duration (~1.22s) plus a short beat to read the final frame.
    private let successHoldDuration: Duration = .milliseconds(1_700)
    /// Matches the unsuccessful animation asset duration (~1.52s) plus a short beat so the failure collapses immediately on completion.
    let failureHoldDuration: Duration = .milliseconds(1_700)
    /// Reads the same setting as `FaceUnlockCoordinator.scanWindowDuration` so
    /// the two separate timers expire together.
    private var scanTimeoutDuration: Duration {
        .seconds(NotchPulseFaceIDSettings.shared.faceDetectionSeconds)
    }
    /// Long enough for the closing spring to fully settle before the window is
    /// hidden/left closed — collapsing state too early made the window visibly pop away.
    let collapseAnimationDuration: Duration = .milliseconds(700)

    private init() {
        windowController.contentView = NSHostingView(rootView: FaceIDOverlayView(controller: self))
        // A display connecting/disconnecting mid-flow can flip notch vs. pill style.
        windowController.onScreenParametersChanged = { [weak self] in
            guard let self else { return }
            self.geometry = self.windowController.currentGeometry
        }
    }

    // MARK: - Armed mode (FaceUnlockCoordinator)

    /// Timestamp when arm() was called, used to ignore accidental hover triggers while the window/pill is animating in.
    private var armedAt: ContinuousClock.Instant?

    /// Arms the overlay for the lock-screen flow: shows the window and keeps it
    /// up until `disarm()`. `onActivate` restarts scanning on hover.
    func arm(onActivate: @escaping () -> Void) {
        isArmed = true
        isPresenting = false
        armedAt = .now
        self.onActivate = onActivate
        resolveTask?.cancel(); resolveTask = nil
        scanTimeoutTask?.cancel(); scanTimeoutTask = nil
        searchingAnimationTask?.cancel(); searchingAnimationTask = nil
        geometry = windowController.currentGeometry
        phase = .closed
        content = .scan(.idle)
        isPillDocked = true
        windowController.show()
        hasPrimedWindow = true // already shown+rendered while closed, same effect as primeWindowIfNeeded
        updateInteractivity()
    }

    /// Truly hides the window. Only call once the lock-screen attempt is
    /// completely done — while armed, resolving an attempt goes back to `.closed`, not this.
    ///
    /// If a success/collapse sequence is already resolving, let it finish
    /// naturally: setting `isArmed = false` is enough, since the already-scheduled
    /// `collapse()` checks `isArmed` once its hold expires and hides for real then.
    func disarm() {
        isArmed = false
        onActivate = nil
        isPillDocked = false
        guard phase != .success, phase != .collapsing else { return }
        resolveTask?.cancel(); resolveTask = nil
        scanTimeoutTask?.cancel(); scanTimeoutTask = nil
        searchingAnimationTask?.cancel(); searchingAnimationTask = nil
        geometry = windowController.currentGeometry
        phase = .closed
        content = .scan(.idle)
        windowController.setInteractive(false)
        windowController.hide()
    }

    /// Shows the idle still; auto-collapses silently (no failure animation) after
    /// `scanTimeoutDuration` if nothing resolves it.
    func beginScanning() {
        resolveTask?.cancel(); resolveTask = nil
        scanTimeoutTask?.cancel()
        searchingAnimationTask?.cancel(); searchingAnimationTask = nil
        geometry = windowController.currentGeometry
        activeUnlockStyle = NotchPulseFaceIDSettings.shared.effectiveUnlockAnimationStyle
        content = .scan(.idle)
        phase = .scanning
        updateInteractivity()

        searchingAnimationTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1200))
            guard let self, !Task.isCancelled, self.phase == .scanning, self.content == .scan(.idle) else { return }
            self.content = .scan(.scanning)
        }

        scanTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: self?.scanTimeoutDuration ?? .seconds(5))
            guard let self, !Task.isCancelled, self.phase == .scanning else { return }
            await self.collapse()
        }
    }

    // MARK: - Window priming (first show only)

    /// On the very first show, `present()`/`presentOnboarding()` would otherwise render
    /// already-expanded with no prior "closed" frame for SwiftUI to animate away from.
    /// This runs one real closed-state show+render pass first, only on that first call.
    private func primeWindowIfNeeded(_ completion: @escaping @MainActor @Sendable () -> Void) {
        guard !hasPrimedWindow else {
            completion()
            return
        }
        hasPrimedWindow = true
        content = .scan(.idle)
        phase = .closed
        windowController.show()
        windowController.displaySynchronously()
        DispatchQueue.main.async {
            completion()
        }
    }

    // MARK: - One-shot mode (onboarding, Face Lab preview)

    /// Shows the overlay in its scanning state. Safe to call again while already visible.
    /// `onRetry` runs on hover after a failed attempt; pass nil to just collapse on hover.
    ///
    /// - Parameter styleOverride: forces `.minimal`/`.original` regardless of the saved
    ///   preference, for the Animation section's live preview.
    func present(styleOverride: UnlockAnimationStyle? = nil, onRetry: (() -> Void)? = nil) {
        // Prevent one-shot presentation from interrupting or clobbering an active lock-screen armed session
        guard !NotchPulseLockMonitor.isScreenActuallyLocked() && !isArmed else { return }
        isPresenting = true
        isArmed = false
        onActivate = onRetry
        resolveTask?.cancel(); resolveTask = nil
        scanTimeoutTask?.cancel(); scanTimeoutTask = nil
        searchingAnimationTask?.cancel(); searchingAnimationTask = nil
        geometry = windowController.currentGeometry
        activeUnlockStyle = styleOverride ?? NotchPulseFaceIDSettings.shared.effectiveUnlockAnimationStyle
        
        primeWindowIfNeeded { [weak self] in
            guard let self else { return }
            self.content = .scan(.idle)
            self.phase = .scanning
            self.windowController.show()
            self.updateInteractivity()

            self.searchingAnimationTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(1200))
                guard let self, !Task.isCancelled, self.phase == .scanning, self.content == .scan(.idle) else { return }
                self.content = .scan(.scanning)
            }
        }
    }

    // MARK: - Onboarding mode (FaceIDEnrollmentController)

    /// Hands the panel to the onboarding flow — this object only owns visibility and
    /// interactivity while `.onboarding` is active; sizing/content is driven by `controller`.
    func presentOnboarding(_ controller: FaceIDEnrollmentController) {
        Self.isOnboardingActive = true
        isPresenting = true
        isArmed = false
        onActivate = nil
        resolveTask?.cancel(); resolveTask = nil
        scanTimeoutTask?.cancel(); scanTimeoutTask = nil
        searchingAnimationTask?.cancel(); searchingAnimationTask = nil

        content = .onboarding(controller)
        geometry = windowController.currentGeometry
        phase = .closed
        isPillDocked = true
        windowController.show()
        windowController.displaySynchronously()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }
            self.phase = .onboarding
            self.updateInteractivity()
        }
    }

    /// Gracefully shrinks the onboarding panel away and hides the window; guarded by
    /// re-checking `content` so a concurrently-started scan cycle can't be interrupted.
    func dismissOnboarding(onCompleted: (() -> Void)? = nil) {
        Self.isOnboardingActive = false
        guard case .onboarding = content else {
            onCompleted?()
            return
        }
        // Drop key/interactivity now, not inside the Task: first-run completion opens
        // Settings this same turn, and a still-key overlay would leave it inactive.
        phase = .collapsing
        updateInteractivity()

        Task { [weak self] in
            guard let self else {
                Self.isOnboardingActive = false
                onCompleted?()
                return
            }
            try? await Task.sleep(for: self.collapseAnimationDuration)
            guard case .onboarding = self.content else {
                Self.isOnboardingActive = false
                onCompleted?()
                return
            }
            Self.isOnboardingActive = false
            self.content = .scan(.idle)
            self.phase = .closed
            self.isPresenting = false
            self.windowController.hide()
            onCompleted?()
        }
    }

    // MARK: - Resolving (shared by both modes)

    /// Resolves the current attempt. Success plays its animation and then
    /// collapses on its own; failure plays its animation and holds until
    /// either the hold expires or the user hovers to retry.
    func finish(success: Bool) {
        searchingAnimationTask?.cancel(); searchingAnimationTask = nil
        resolveTask?.cancel(); resolveTask = nil
        scanTimeoutTask?.cancel(); scanTimeoutTask = nil

        // Unlock Animation → None just skips the success/failure video; phase and
        // retry behavior are unaffected. Reads the cycle's captured style, not live settings.
        let shouldAnimate = activeUnlockStyle != .none
        content = shouldAnimate ? .scan(success ? .success : .failure) : .scan(.idle)
        withAnimation(FaceIDOverlayGeometry.springAnimation) {
            phase = success ? .success : .failure
        }
        updateInteractivity()

        let hold = shouldAnimate ? (success ? successHoldDuration : failureHoldDuration) : Duration.milliseconds(400)
        resolveTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: hold)
            guard !Task.isCancelled else { return }
            await self.collapse()
        }
    }

    private(set) var isHovering: Bool = false
    private var pendingHoverActivationTask: Task<Void, Never>?

    func setHovering(_ hovering: Bool) {
        isHovering = hovering
        if !hovering {
            pendingHoverActivationTask?.cancel()
            pendingHoverActivationTask = nil
        }
    }

    /// Hover-driven activation: wakes from a closed/armed state, or retries from a held
    /// failure frame. No-op during scanning/success/collapsing.
    func activate(force: Bool = false) {
        if !force {
            // Gated here rather than in `updateInteractivity()` so the cosmetic hover bump
            // stays unaffected — only the retry itself is removed.
            guard NotchPulseFaceIDSettings.shared.retryOnHover else { return }

            // Ignore accidental hover triggers while the armed silhouette is animating in
            if let armedAt, ContinuousClock.now - armedAt < .milliseconds(500) {
                return
            }
        }

        switch phase {
        case .closed, .failure:
            guard let onActivate else {
                if phase == .failure { Task { await collapse() } }
                return
            }
            if !isArmed {
                resolveTask?.cancel(); resolveTask = nil
                activeUnlockStyle = NotchPulseFaceIDSettings.shared.effectiveUnlockAnimationStyle
                content = .scan(.idle)
                phase = .scanning
                updateInteractivity()
            }
            onActivate()
        case .scanning, .success, .collapsing, .onboarding:
            break
        }
    }

    /// Collapses gracefully: animates shut, then either leaves the window
    /// at rest (closed, still on-screen, hover-reactive) if armed, or
    /// orders it out entirely if not.
    func collapse() async {
        guard phase != .closed, phase != .collapsing else { return }
        searchingAnimationTask?.cancel(); searchingAnimationTask = nil
        scanTimeoutTask?.cancel(); scanTimeoutTask = nil
        phase = .collapsing
        updateInteractivity()
        try? await Task.sleep(for: collapseAnimationDuration)
        guard phase == .collapsing else { return }

        // Same re-measure as `disarm()` — self-corrects a geometry captured
        // during a mid-wake reading before the panel settles to `.closed`.
        geometry = windowController.currentGeometry
        content = .scan(.idle)
        if isArmed {
            phase = .closed
            updateInteractivity()
        } else {
            phase = .closed
            isPresenting = false
            windowController.hide()
        }
    }

    /// Tears the overlay down without any resolve animation. Deliberately a no-op while
    /// success/collapsing is in flight — interrupting that made the window vanish abruptly.
    func dismissImmediately() {
        guard phase != .success, phase != .collapsing else { return }
        searchingAnimationTask?.cancel(); searchingAnimationTask = nil
        resolveTask?.cancel(); resolveTask = nil
        scanTimeoutTask?.cancel(); scanTimeoutTask = nil
        phase = .closed
        content = .scan(.idle)
        isPillDocked = false
        isPresenting = false
        windowController.setInteractive(false)
        windowController.hide()
    }

    private func updateInteractivity() {
        // Click-through otherwise, so the overlay never intercepts anything it doesn't
        // need to. Onboarding additionally needs key so its text field can receive keystrokes.
        windowController.setInteractive(isArmed || phase == .failure || phase == .onboarding, key: phase == .onboarding)
    }

    /// Called by `FaceIDOverlayView` whenever the visible panel's own frame
    /// changes (step change, expand/collapse, hover bump, …) — see
    /// `FaceIDOverlayWindowController.updateMousePassthrough()`.
    func updateInteractiveContentRect(_ rect: CGRect?) {
        windowController.setInteractiveContentRect(rect)
    }
}
