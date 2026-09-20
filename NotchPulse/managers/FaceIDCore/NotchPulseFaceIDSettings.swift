//
//  NotchPulseFaceIDSettings.swift
//  NotchPulse
//
//  Backed directly by `UserDefaults.standard` — each property's `didSet`
//  writes through immediately, so there's no explicit "save" step.
//

import Foundation
import Observation
import Defaults

/// How long the Touch-ID-unlocked session may sit idle before it re-locks.
enum AutoLockInterval: Int, CaseIterable, Identifiable {
    case oneDay = 1
    case sevenDays = 7
    case fourteenDays = 14
    case thirtyDays = 30

    var id: Int { rawValue }

    var title: String { rawValue == 1 ? "1 day" : "\(rawValue) days" }

    var duration: TimeInterval { TimeInterval(rawValue) * 24 * 60 * 60 }

    /// Position in `allCases`, used to drive the discrete 4-stop slider.
    var sliderIndex: Double {
        Double(Self.allCases.firstIndex(of: self) ?? 0)
    }

    static func from(sliderIndex: Double) -> AutoLockInterval {
        let clamped = Int(sliderIndex.rounded())
        return allCases.indices.contains(clamped) ? allCases[clamped] : .sevenDays
    }
}

/// Unlock success/failure animation style shown in the notch overlay.
enum UnlockAnimationStyle: String, CaseIterable, Identifiable {
    case none
    case minimal
    case original

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "None"
        case .minimal: return "Minimal"
        case .original: return "Original"
        }
    }

    /// The styles the picker offers; `.none` is still a valid stored value but is now produced by the "Show animation" toggle, not a tile.
    static let selectableCases: [UnlockAnimationStyle] = [.minimal, .original]
}

/// What can prompt Face Unlock. Multi-select; at least one is always kept
/// selected, since a Mac with none armed would never show the notch.
enum UnlockTrigger: String, CaseIterable, Identifiable {
    /// The display turned back on (see `LockEventKind.wake`).
    case onWake
    /// The screen just became locked, no wake involved.
    case onLock
    /// Pressing space on the lock screen starts a scan. The lock screen's
    /// Secure Event Input blocks normal event taps, so this is detected via
    /// IOKit HID instead (see `NotchPulseSpaceKeyMonitor`), requiring Input Monitoring.
    case onSpace

    var id: String { rawValue }

    var title: String {
        switch self {
        case .onWake: return "On wake"
        case .onLock: return "On lock"
        case .onSpace: return "On space"
        }
    }

    var iconName: String {
        switch self {
        case .onWake: return "zzz"
        case .onLock: return "lock.display"
        case .onSpace: return "space"
        }
    }
}

@Observable
@MainActor
final class NotchPulseFaceIDSettings {
    static let shared = NotchPulseFaceIDSettings()

    private enum Key {
        static let isFaceUnlockEnabled = "NotchPulseFaceIDSettings.isFaceUnlockEnabled"
        static let matchThreshold = "NotchPulseFaceIDSettings.matchThreshold"
        static let livenessChecksEnabled = "NotchPulseFaceIDSettings.livenessChecksEnabled"
        static let livenessMode = "NotchPulseFaceIDSettings.livenessMode"
        static let minimumFaceWidth = "NotchPulseFaceIDSettings.minimumFaceWidth"
        static let unlockAnimationStyle = "NotchPulseFaceIDSettings.unlockAnimationStyle"
        static let showUnlockAnimation = "NotchPulseFaceIDSettings.showUnlockAnimation"
        /// Legacy bool key — read once during migration, then ignored.
        static let playUnlockAnimation = "NotchPulseFaceIDSettings.playUnlockAnimation"
        static let unlockTriggers = "NotchPulseFaceIDSettings.unlockTriggers"
        static let retryOnHover = "NotchPulseFaceIDSettings.retryOnHover"
        static let faceDetectionSeconds = "NotchPulseFaceIDSettings.faceDetectionSeconds"
        static let autoRetryOnce = "NotchPulseFaceIDSettings.autoRetryOnce"
        static let hapticFeedbackEnabled = "NotchPulseFaceIDSettings.hapticFeedbackEnabled"
        static let preferredDisplayID = "NotchPulseFaceIDSettings.preferredDisplayID"
        static let preferredDisplayName = "NotchPulseFaceIDSettings.preferredDisplayName"
        static let autoLockIntervalDays = "NotchPulseFaceIDSettings.autoLockIntervalDays"
        static let defaultCameraID = "NotchPulseFaceIDSettings.defaultCameraID"
        static let builtInDisplayCameraID = "NotchPulseFaceIDSettings.builtInDisplayCameraID"
        static let externalDisplayCameraID = "NotchPulseFaceIDSettings.externalDisplayCameraID"
        static let hasCompletedOnboarding = "NotchPulseFaceIDSettings.hasCompletedOnboarding"
        static let onboardingResumeStep = "NotchPulseFaceIDSettings.onboardingResumeStep"
        static let hasAcknowledgedSecurityNotice = "NotchPulseFaceIDSettings.hasAcknowledgedSecurityNotice"
        static let isSystemAuthFaceIDEnabled = "NotchPulseFaceIDSettings.isSystemAuthFaceIDEnabled"
        static let isTerminalQuickAuthEnabled = "NotchPulseFaceIDSettings.isTerminalQuickAuthEnabled"
        static let useAppleAuthFallback = "NotchPulseFaceIDSettings.useAppleAuthFallback"
    }

    @ObservationIgnored private let defaults = UserDefaults.standard

    var isFaceUnlockEnabled: Bool {
        didSet { defaults.set(isFaceUnlockEnabled, forKey: Key.isFaceUnlockEnabled) }
    }
    var matchThreshold: Float {
        didSet { defaults.set(matchThreshold, forKey: Key.matchThreshold) }
    }
    /// Master switch for liveness checking. Off means face recognition
    /// alone decides an unlock — a photo of the enrolled user would pass.
    var livenessChecksEnabled: Bool {
        didSet { defaults.set(livenessChecksEnabled, forKey: Key.livenessChecksEnabled) }
    }
    /// Light (deny-only) vs Heavy (deny plus a required proof of life) —
    /// see `LivenessMode`.
    var livenessMode: LivenessMode {
        didSet { defaults.set(livenessMode.rawValue, forKey: Key.livenessMode) }
    }
    /// Mirrored into `NotchPulseFaceRecognitionPipeline.minimumProminentFaceWidth` on
    /// every change, since that's read from a background `nonisolated` context.
    var minimumFaceWidth: Float {
        didSet {
            defaults.set(minimumFaceWidth, forKey: Key.minimumFaceWidth)
            NotchPulseFaceRecognitionPipeline.minimumProminentFaceWidth = minimumFaceWidth
        }
    }
    /// The remembered choice (`.minimal`/`.original` only); `showUnlockAnimation`
    /// tracks on/off separately so toggling back on restores the prior pick.
    /// Read `effectiveUnlockAnimationStyle`, not this, to decide what to show.
    var unlockAnimationStyle: UnlockAnimationStyle {
        didSet { defaults.set(unlockAnimationStyle.rawValue, forKey: Key.unlockAnimationStyle) }
    }
    var showUnlockAnimation: Bool {
        didSet { defaults.set(showUnlockAnimation, forKey: Key.showUnlockAnimation) }
    }

    /// What the overlay should actually render — the pick, or `.none` when
    /// animations are switched off entirely.
    var effectiveUnlockAnimationStyle: UnlockAnimationStyle {
        showUnlockAnimation ? unlockAnimationStyle : .none
    }

    /// Which signals arm Face Unlock. Persisted as raw-value strings; the
    /// setter refuses to store an empty set (see `UnlockTrigger`).
    var unlockTriggers: Set<UnlockTrigger> {
        didSet {
            // Belt-and-braces behind the picker's own min-one rule. This
            // reassignment re-enters didSet once, then terminates since the
            // corrected value is never itself empty.
            if unlockTriggers.isEmpty {
                unlockTriggers = oldValue.isEmpty ? Set(UnlockTrigger.allCases) : oldValue
            }
            defaults.set(unlockTriggers.map(\.rawValue), forKey: Key.unlockTriggers)
        }
    }
    var retryOnHover: Bool {
        didSet { defaults.set(retryOnHover, forKey: Key.retryOnHover) }
    }
    /// How long each scan cycle looks for a face before giving up. Must stay
    /// equal to `NotchPulseFaceUnlockCoordinator.scanWindowDuration` and
    /// `FaceIDOverlayController.scanTimeoutDuration`.
    var faceDetectionSeconds: Int {
        didSet {
            // Only reassign when clamping actually changes the value —
            // unconditional reassignment would recurse infinitely, since the
            // slider only ever produces already-in-range values.
            let clamped = min(max(faceDetectionSeconds, Self.faceDetectionRange.lowerBound),
                               Self.faceDetectionRange.upperBound)
            guard clamped == faceDetectionSeconds else {
                faceDetectionSeconds = clamped
                return
            }
            defaults.set(faceDetectionSeconds, forKey: Key.faceDetectionSeconds)
        }
    }
    var autoRetryOnce: Bool {
        didSet { defaults.set(autoRetryOnce, forKey: Key.autoRetryOnce) }
    }
    /// Trackpad haptic on hovering the notch/pill and on a successful unlock —
    /// see `NotchOverlayView`'s hover handler and `.onChange(of: controller.phase)`.
    var hapticFeedbackEnabled: Bool {
        didSet { defaults.set(hapticFeedbackEnabled, forKey: Key.hapticFeedbackEnabled) }
    }

    static let faceDetectionRange = 3...10

    /// Which display Face Unlock shows on. `nil` means `NotchGeometry.preferredScreen()`'s
    /// default, re-evaluated live; a pinned display has deliberately no
    /// fallback if disconnected (see `NotchPulseFaceUnlockCoordinator.evaluateTrigger()`).
    var preferredDisplayID: String? {
        didSet { defaults.set(preferredDisplayID, forKey: Key.preferredDisplayID) }
    }
    /// The chosen display's name at pick time — cosmetic only, so the row can
    /// show something recognizable when that display is disconnected.
    var preferredDisplayName: String? {
        didSet { defaults.set(preferredDisplayName, forKey: Key.preferredDisplayName) }
    }
    /// Enforced by `NotchPulseSessionAutoLocker`, not here — this is only the stored
    /// preference.
    var autoLockInterval: AutoLockInterval {
        didSet { defaults.set(autoLockInterval.rawValue, forKey: Key.autoLockIntervalDays) }
    }
    /// Device `uniqueID`s, not device objects — devices can disconnect/
    /// reconnect between launches, but their unique ID is stable.
    var defaultCameraID: String? {
        didSet { defaults.set(defaultCameraID, forKey: Key.defaultCameraID) }
    }
    var builtInDisplayCameraID: String? {
        didSet { defaults.set(builtInDisplayCameraID, forKey: Key.builtInDisplayCameraID) }
    }
    var externalDisplayCameraID: String? {
        didSet { defaults.set(externalDisplayCameraID, forKey: Key.externalDisplayCameraID) }
    }

    /// Gates first-run onboarding — `AppDelegate` shows it instead of the
    /// Settings window until this is `true`. Set once, by `FaceIDEnrollmentController`
    /// on the true first-run flow reaching `.complete`.
    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Key.hasCompletedOnboarding) }
    }
    /// Where to resume first-run onboarding if the app quit mid-flow; `nil`
    /// starts fresh at `.intro`. Steps depending on in-memory capture state
    /// collapse to `.preSetup` before storing, since that state doesn't
    /// survive a relaunch — see `FaceIDOnboardingStep.resumeTarget`.
    var onboardingResumeStep: FaceIDOnboardingStep? {
        didSet { defaults.set(onboardingResumeStep?.rawValue, forKey: Key.onboardingResumeStep) }
    }
    /// Gates the one-time post-update notice for users who completed onboarding before the
    /// security-disclaimer step existed. Set alongside `hasCompletedOnboarding` for anyone
    /// finishing normal onboarding (which now includes that step), and separately by
    /// `FaceIDEnrollmentController.startPostUpdateNotice()` once the standalone catch-up notice is
    /// acknowledged. Defaults `false`, so an upgrading 1.0 install (where this key has never
    /// been written) correctly triggers the catch-up flow once.
    var hasAcknowledgedSecurityNotice: Bool {
        didSet { defaults.set(hasAcknowledgedSecurityNotice, forKey: Key.hasAcknowledgedSecurityNotice) }
    }
    var isSystemAuthFaceIDEnabled: Bool {
        didSet {
            defaults.set(isSystemAuthFaceIDEnabled, forKey: Key.isSystemAuthFaceIDEnabled)
            Defaults[.enableFaceIDForSystemPrompts] = isSystemAuthFaceIDEnabled
        }
    }
    var isTerminalQuickAuthEnabled: Bool {
        didSet { defaults.set(isTerminalQuickAuthEnabled, forKey: Key.isTerminalQuickAuthEnabled) }
    }
    var useAppleAuthFallback: Bool {
        didSet { defaults.set(useAppleAuthFallback, forKey: Key.useAppleAuthFallback) }
    }

    private init() {
        // Enabled by default — onboarding already enrolled a face and set a
        // password specifically to use Face Unlock.
        isFaceUnlockEnabled = defaults.object(forKey: Key.isFaceUnlockEnabled) as? Bool ?? true
        // Matches `MatchConfidenceLevel.standard` — see RecognitionSettingsPage.swift.
        matchThreshold = defaults.object(forKey: Key.matchThreshold) as? Float ?? 0.66
        livenessChecksEnabled = defaults.object(forKey: Key.livenessChecksEnabled) as? Bool ?? true
        // Light by default — Heavy requires a blink/pose/depth signal a
        // still, non-blinking user may never produce, while Light still
        // catches the main attack (a photo on a phone screen).
        livenessMode = defaults.string(forKey: Key.livenessMode)
            .flatMap(LivenessMode.init(rawValue:)) ?? .light
        // Matches `DetectionDistanceLevel.standard` — see RecognitionSettingsPage.swift.
        minimumFaceWidth = defaults.object(forKey: Key.minimumFaceWidth) as? Float ?? 0.21

        // Resolve the stored style first, `.none` included, then split it
        // into the pick + the on/off flag the UI now works in.
        let storedStyle: UnlockAnimationStyle
        if let raw = defaults.string(forKey: Key.unlockAnimationStyle),
           let style = UnlockAnimationStyle(rawValue: raw) {
            storedStyle = style
        } else if let legacy = defaults.object(forKey: Key.playUnlockAnimation) as? Bool {
            // Migrate the oldest on/off toggle: off → none, on → original.
            storedStyle = legacy ? .original : .none
        } else {
            storedStyle = .original
        }
        // A stored `.none` becomes "off, remembering .original" so
        // switching back on has something to restore.
        unlockAnimationStyle = storedStyle == .none ? .original : storedStyle
        showUnlockAnimation = defaults.object(forKey: Key.showUnlockAnimation) as? Bool
            ?? (storedStyle != .none)

        // On wake/lock by default, not on space — `.onSpace` needs Input
        // Monitoring, which a fresh install shouldn't request unprompted.
        let storedTriggers = (defaults.array(forKey: Key.unlockTriggers) as? [String])?
            .compactMap { raw -> UnlockTrigger? in
                // "onActivity" was merged into "onWake"; keep old installs working.
                if raw == "onActivity" { return .onWake }
                return UnlockTrigger(rawValue: raw)
            }
        unlockTriggers = storedTriggers.map(Set.init).flatMap { $0.isEmpty ? nil : $0 }
            ?? [.onWake, .onLock]
        retryOnHover = defaults.object(forKey: Key.retryOnHover) as? Bool ?? true
        faceDetectionSeconds = (defaults.object(forKey: Key.faceDetectionSeconds) as? Int)
            .map { min(max($0, Self.faceDetectionRange.lowerBound), Self.faceDetectionRange.upperBound) }
            ?? 5
        autoRetryOnce = defaults.object(forKey: Key.autoRetryOnce) as? Bool ?? false
        hapticFeedbackEnabled = defaults.object(forKey: Key.hapticFeedbackEnabled) as? Bool ?? true
        preferredDisplayID = defaults.string(forKey: Key.preferredDisplayID)
        preferredDisplayName = defaults.string(forKey: Key.preferredDisplayName)

        // Defaults to 7 days — long enough not to nag daily users, short
        // enough not to leave an abandoned session live indefinitely.
        autoLockInterval = (defaults.object(forKey: Key.autoLockIntervalDays) as? Int)
            .flatMap(AutoLockInterval.init(rawValue:)) ?? .sevenDays
        defaultCameraID = defaults.string(forKey: Key.defaultCameraID)
        builtInDisplayCameraID = defaults.string(forKey: Key.builtInDisplayCameraID)
        externalDisplayCameraID = defaults.string(forKey: Key.externalDisplayCameraID)

        hasCompletedOnboarding = defaults.object(forKey: Key.hasCompletedOnboarding) as? Bool ?? false
        onboardingResumeStep = defaults.string(forKey: Key.onboardingResumeStep)
            .flatMap(FaceIDOnboardingStep.init(rawValue:))
        hasAcknowledgedSecurityNotice = defaults.object(forKey: Key.hasAcknowledgedSecurityNotice) as? Bool ?? false
        isSystemAuthFaceIDEnabled = defaults.object(forKey: Key.isSystemAuthFaceIDEnabled) as? Bool
            ?? Defaults[.enableFaceIDForSystemPrompts]
        isTerminalQuickAuthEnabled = defaults.object(forKey: Key.isTerminalQuickAuthEnabled) as? Bool ?? true
        useAppleAuthFallback = defaults.object(forKey: Key.useAppleAuthFallback) as? Bool ?? true

        // Push into the nonisolated mirror immediately, or NotchPulseFaceRecognitionPipeline
        // would keep its own default until the slider is first touched.
        NotchPulseFaceRecognitionPipeline.minimumProminentFaceWidth = minimumFaceWidth
    }
}
