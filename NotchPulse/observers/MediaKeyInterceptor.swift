import Foundation
import AppKit
import ApplicationServices
import Defaults
import AVFoundation

private let kSystemDefinedEventType = CGEventType(rawValue: 14)!

fileprivate enum NXKeyType: Int {
    case soundUp = 0
    case soundDown = 1
    case brightnessUp = 2
    case brightnessDown = 3
    case mute = 7
    case keyboardBrightnessUp = 21
    case keyboardBrightnessDown = 22
}

final class MediaKeyInterceptor {
    static let shared = MediaKeyInterceptor()
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let step: Float = 1.0 / 16.0
    private let feedbackQueue = DispatchQueue(label: "com.notchpulse.feedbackAudio", qos: .userInteractive)
    private var audioPlayers: [AVAudioPlayer] = []
    private var nextAudioPlayerIndex: Int = 0
    private var didAttemptAudioPreload: Bool = false

    private struct HoldState {
        let keyType: NXKeyType
        let stepDivisor: Float
        let isKeyboardBacklight: Bool
        let alternateScreen: Bool
        var lastHeartbeatAt: ContinuousClock.Instant
        var isRamping: Bool
        var accumulatedSoundTravel: Float
        var lastSoundPlayedAt: ContinuousClock.Instant
    }

    private var activeHold: HoldState?
    private var holdArmTimer: Timer?
    private var holdRampTimer: Timer?

    var isIntercepting: Bool { eventTap != nil }
    
    private init() {}
    
    // MARK: - Accessibility (via XPC)
    
    func requestAccessibilityAuthorization() {
        XPCHelperClient.shared.requestAccessibilityAuthorization()
    }
    
    func ensureAccessibilityAuthorization(promptIfNeeded: Bool = false) async -> Bool {
        await XPCHelperClient.shared.ensureAccessibilityAuthorization(promptIfNeeded: promptIfNeeded)
    }
    
    // MARK: - Event Tap
    
    func start(promptIfNeeded: Bool = false) async {
        guard eventTap == nil else { return }
        
        // Ensure HUD replacement or inline HUD is enabled
        guard Defaults[.hudReplacement] || Defaults[.inlineHUD] else {
            stop()
            return
        }
        
        // Check accessibility authorization
        let authorized = await XPCHelperClient.shared.isAccessibilityAuthorized()
        if !authorized {
            if promptIfNeeded {
                let granted = await ensureAccessibilityAuthorization(promptIfNeeded: true)
                guard granted else { return }
            } else {
                return
            }
        }
        
        let mask = CGEventMask(1 << kSystemDefinedEventType.rawValue)
        eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, cgEvent, userInfo in
                guard let userInfo else { return Unmanaged.passRetained(cgEvent) }
                let interceptor = Unmanaged<MediaKeyInterceptor>.fromOpaque(userInfo).takeUnretainedValue()
                
                // macOS automatically disables event taps when system load spikes or an event takes slightly longer.
                // Immediately re-enable the tap to prevent falling back to native macOS HUD UI.
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let eventTap = interceptor.eventTap {
                        CGEvent.tapEnable(tap: eventTap, enable: true)
                    }
                    if let nsEvent = NSEvent(cgEvent: cgEvent),
                       nsEvent.type == .systemDefined,
                       nsEvent.subtype.rawValue == 8 {
                        let data1 = nsEvent.data1
                        let keyCode = (data1 & 0xFFFF_0000) >> 16
                        if NXKeyType(rawValue: keyCode) != nil {
                            return nil
                        }
                    }
                    return Unmanaged.passRetained(cgEvent)
                }
                
                return interceptor.handleEvent(cgEvent)
            },
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )
        
        if let eventTap {
            runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
            if let runLoopSource {
                CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            }
            CGEvent.tapEnable(tap: eventTap, enable: true)
            warmAudioFeedbackAsync()
        }
    }
    
    func stop() {
        stopHoldRamp()
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        runLoopSource = nil
        eventTap = nil
    }
    
    // MARK: - Event Handling
    
    private func handleEvent(_ cgEvent: CGEvent) -> Unmanaged<CGEvent>? {
        // Ensure the CGEvent has a valid type before converting to NSEvent
        guard cgEvent.type != .null else {
            return Unmanaged.passRetained(cgEvent)
        }
        guard let nsEvent = NSEvent(cgEvent: cgEvent),
              nsEvent.type == .systemDefined,
              nsEvent.subtype.rawValue == 8 else {
            return Unmanaged.passRetained(cgEvent)
        }
        
        let data1 = nsEvent.data1
        let keyCode = (data1 & 0xFFFF_0000) >> 16
        let stateByte = ((data1 & 0xFF00) >> 8)
        let isRepeat = (nsEvent.data2 & 0x1) != 0
        
        // Match against media keys handled by NotchPulse
        guard let keyType = NXKeyType(rawValue: keyCode) else {
            return Unmanaged.passRetained(cgEvent)
        }
        
        // 0xA = key down, 0xB = key up.
        // Completely swallow key-up (0xB) and non-down states so macOS Bezel/OSD never triggers on key release!
        if stateByte == 0xB {
            if activeHold?.keyType == keyType {
                stopHoldRamp()
            }
            return nil
        }
        guard stateByte == 0xA else {
            return nil
        }
        
        let flags = nsEvent.modifierFlags
        let option = flags.contains(.option)
        let shift = flags.contains(.shift)
        let command = flags.contains(.command)
        let control = flags.contains(.control)
        
        // Handle option key action (without shift)
        if option && !shift {
            stopHoldRamp()
            if !isRepeat, handleOptionAction(for: keyType, command: command) {
                return nil
            }
            return nil
        }
        
        // Handle normal key press & smooth hold ramp
        handleKeyPress(keyType: keyType, option: option, shift: shift, command: command, control: control, isRepeat: isRepeat)
        return nil
    }
    
    private func handleOptionAction(for keyType: NXKeyType, command: Bool) -> Bool {
        let action = Defaults[.optionKeyAction]
        
        switch action {
        case .openSettings:
            openSystemSettings(for: keyType, command: command)
            return true
        case .showHUD:
            showHUD(for: keyType, command: command)
            return true
        case .none:
            return true
        }
    }
    
    private func warmAudioFeedbackAsync() {
        feedbackQueue.async { [weak self] in
            guard let self else { return }
            if self.isFeedbackSoundEnabledOnQueue() {
                self.prepareAudioPlayersIfNeededOnQueue()
            }
        }
    }

    // Must only be called on `feedbackQueue` so AVAudioPlayer init & CoreAudio graph setup never block Main/CGEventTap.
    private func prepareAudioPlayersIfNeededOnQueue() {
        guard !didAttemptAudioPreload else { return }
        didAttemptAudioPreload = true

        let defaultPath = "/System/Library/LoginPlugins/BezelServices.loginPlugin/Contents/Resources/volume.aiff"
        guard FileManager.default.fileExists(atPath: defaultPath) else {
            print("⚠️ [MediaKeyInterceptor] Default bezel audio not found at: \(defaultPath)")
            return
        }

        let url = URL(fileURLWithPath: defaultPath)
        var loaded: [AVAudioPlayer] = []
        // Small 2-player pool lets overlapping 75ms ticks play without calling player.stop() on active samples.
        for _ in 0..<2 {
            do {
                let player = try AVAudioPlayer(contentsOf: url)
                player.volume = 1.0
                player.numberOfLoops = 0
                player.prepareToPlay()
                loaded.append(player)
            } catch {
                print("⚠️ [MediaKeyInterceptor] Failed to init AVAudioPlayer with default path \(defaultPath): \(error.localizedDescription)")
                break
            }
        }
        audioPlayers = loaded
    }

    private var cachedFeedbackCheckTime: ContinuousClock.Instant?
    private var cachedFeedbackEnabled: Bool = false

    private func isFeedbackSoundEnabledOnQueue() -> Bool {
        let now = ContinuousClock.now
        if let last = cachedFeedbackCheckTime, now - last < .seconds(5) {
            return cachedFeedbackEnabled
        }
        let feedback = UserDefaults.standard.persistentDomain(forName: "NSGlobalDomain")?["com.apple.sound.beep.feedback"] as? Int
        cachedFeedbackEnabled = (feedback == 1)
        cachedFeedbackCheckTime = now
        return cachedFeedbackEnabled
    }

    private func playFeedbackSound() {
        feedbackQueue.async { [weak self] in
            guard let self, self.isFeedbackSoundEnabledOnQueue() else { return }
            self.prepareAudioPlayersIfNeededOnQueue()
            guard !self.audioPlayers.isEmpty else { return }

            let player = self.audioPlayers[self.nextAudioPlayerIndex % self.audioPlayers.count]
            self.nextAudioPlayerIndex = (self.nextAudioPlayerIndex + 1) % self.audioPlayers.count
            if player.isPlaying {
                player.currentTime = 0
            }
            player.play()
        }
    }

    private func handleKeyPress(
        keyType: NXKeyType,
        option: Bool,
        shift: Bool,
        command: Bool,
        control: Bool,
        isRepeat: Bool
    ) {
        let stepDivisor: Float = (option && shift) ? 4.0 : 1.0
        let now = ContinuousClock.now

        if keyType == .mute {
            stopHoldRamp()
            guard !isRepeat else { return }
            runOnMainActorSync {
                VolumeManager.shared.toggleMuteAction()
            }
            return
        }

        let isKeyboardBacklight = (keyType == .keyboardBrightnessUp || keyType == .keyboardBrightnessDown)
            || ((keyType == .brightnessUp || keyType == .brightnessDown) && command)

        if isRepeat, var existing = activeHold, existing.keyType == keyType {
            existing.lastHeartbeatAt = now
            activeHold = existing
            if !existing.isRamping {
                startHoldRampTimer()
            }
            // While 60Hz continuous ramp is active, ignore coarse discrete OS repeat bursts.
            return
        }

        // Fresh initial press: apply crisp 1-notch step immediately (0ms latency) and arm smooth 60Hz ramp.
        stopHoldRamp()
        applyStep(
            keyType: keyType,
            magnitude: step / stepDivisor,
            keyboard: isKeyboardBacklight,
            alternateScreen: control,
            playSound: true
        )

        activeHold = HoldState(
            keyType: keyType,
            stepDivisor: stepDivisor,
            isKeyboardBacklight: isKeyboardBacklight,
            alternateScreen: control,
            lastHeartbeatAt: now,
            isRamping: false,
            accumulatedSoundTravel: 0,
            lastSoundPlayedAt: now
        )

        let timer = Timer(timeInterval: 0.21, repeats: false) { [weak self] _ in
            self?.startHoldRampTimer()
        }
        RunLoop.main.add(timer, forMode: .common)
        holdArmTimer = timer
    }

    private func startHoldRampTimer() {
        holdArmTimer?.invalidate()
        holdArmTimer = nil
        guard holdRampTimer == nil, var state = activeHold else { return }
        state.isRamping = true
        activeHold = state

        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tickHoldRamp()
        }
        RunLoop.main.add(timer, forMode: .common)
        holdRampTimer = timer
    }

    private func stopHoldRamp() {
        holdArmTimer?.invalidate()
        holdArmTimer = nil
        holdRampTimer?.invalidate()
        holdRampTimer = nil
        activeHold = nil
    }

    private func tickHoldRamp() {
        guard var state = activeHold else {
            stopHoldRamp()
            return
        }

        let now = ContinuousClock.now
        // Safety watchdog: stop cleanly if no key-repeat heartbeat arrives within 450ms (e.g. lost keyUp).
        guard now - state.lastHeartbeatAt <= .milliseconds(450) else {
            stopHoldRamp()
            return
        }

        // 60Hz smooth glide (~0.69/sec = ~1.45s full 0%..100% travel; 4x finer when Option+Shift is held).
        let frameMagnitude = Float(0.0115) / max(state.stepDivisor, 0.25)
        var shouldPlaySound = false

        if state.keyType == .soundUp || state.keyType == .soundDown {
            state.accumulatedSoundTravel += frameMagnitude
            if state.accumulatedSoundTravel >= step, now - state.lastSoundPlayedAt >= .milliseconds(75) {
                state.accumulatedSoundTravel -= step
                state.lastSoundPlayedAt = now
                shouldPlaySound = true
            }
        }
        activeHold = state

        applyStep(
            keyType: state.keyType,
            magnitude: frameMagnitude,
            keyboard: state.isKeyboardBacklight,
            alternateScreen: state.alternateScreen,
            playSound: shouldPlaySound
        )
    }

    private func applyStep(
        keyType: NXKeyType,
        magnitude: Float,
        keyboard: Bool,
        alternateScreen: Bool,
        playSound: Bool
    ) {
        runOnMainActorSync {
            switch keyType {
            case .soundUp:
                if playSound { self.playFeedbackSound() }
                let target = max(0, min(1, VolumeManager.shared.rawVolume + magnitude))
                VolumeManager.shared.setAbsolute(target)
                NotchPulseViewCoordinator.shared.toggleSneakPeek(status: true, type: .volume, value: CGFloat(target))
            case .soundDown:
                if playSound { self.playFeedbackSound() }
                let target = max(0, min(1, VolumeManager.shared.rawVolume - magnitude))
                VolumeManager.shared.setAbsolute(target)
                NotchPulseViewCoordinator.shared.toggleSneakPeek(status: true, type: .volume, value: CGFloat(target))
            case .brightnessUp, .keyboardBrightnessUp:
                if keyboard {
                    KeyboardBacklightManager.shared.setRelative(delta: magnitude)
                } else {
                    BrightnessManager.shared.setRelative(delta: magnitude, alternateScreen: alternateScreen)
                }
            case .brightnessDown, .keyboardBrightnessDown:
                if keyboard {
                    KeyboardBacklightManager.shared.setRelative(delta: -magnitude)
                } else {
                    BrightnessManager.shared.setRelative(delta: -magnitude, alternateScreen: alternateScreen)
                }
            case .mute:
                VolumeManager.shared.toggleMuteAction()
            }
        }
    }

    private func runOnMainActorSync(_ block: @escaping @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                block()
            }
        } else {
            Task { @MainActor in
                block()
            }
        }
    }
    
    private func showHUD(for keyType: NXKeyType, command: Bool) {
        Task { @MainActor in
            switch keyType {
            case .soundUp, .soundDown, .mute:
                let v = VolumeManager.shared.rawVolume
                NotchPulseViewCoordinator.shared.toggleSneakPeek(status: true, type: .volume, value: CGFloat(v))
            case .brightnessUp, .brightnessDown:
                if command {
                    let v = KeyboardBacklightManager.shared.rawBrightness
                    NotchPulseViewCoordinator.shared.toggleSneakPeek(status: true, type: .backlight, value: CGFloat(v))
                } else {
                    let v = BrightnessManager.shared.rawBrightness
                    NotchPulseViewCoordinator.shared.toggleSneakPeek(status: true, type: .brightness, value: CGFloat(v))
                }
            case .keyboardBrightnessUp, .keyboardBrightnessDown:
                let v = KeyboardBacklightManager.shared.rawBrightness
                NotchPulseViewCoordinator.shared.toggleSneakPeek(status: true, type: .backlight, value: CGFloat(v))
            }
        }
    }
    
    private func openSystemSettings(for keyType: NXKeyType, command: Bool) {
        let urlString: String
        
        switch keyType {
        case .soundUp, .soundDown, .mute:
            urlString = "x-apple.systempreferences:com.apple.preference.sound"
        case .brightnessUp, .brightnessDown:
            if command {
                urlString = "x-apple.systempreferences:com.apple.preference.keyboard"
            } else {
                urlString = "x-apple.systempreferences:com.apple.preference.displays"
            }
        case .keyboardBrightnessUp, .keyboardBrightnessDown:
            urlString = "x-apple.systempreferences:com.apple.preference.keyboard"
        }
        
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
