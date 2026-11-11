import AppKit
import Combine
import CoreAudio
import Foundation

final class VolumeManager: NSObject, ObservableObject, @unchecked Sendable {
    static let shared = VolumeManager()

    @Published private(set) var rawVolume: Float = 0
    @Published private(set) var isMuted: Bool = false
    @Published private(set) var lastChangeAt: Date = .distantPast
    private(set) var lastDeviceSwitchAt: Date = .distantPast

    let visibleDuration: TimeInterval = 1.2

    private var didInitialFetch = false
    private let step: Float32 = 1.0 / 16.0

    // Optimistic restore volume tracked on MainActor for instant unmute HUD feedback.
    private var optimisticRestoreVolume: Float32 = 0.2

    // Dedicated CoreAudio queue + coalesced write mailbox so HAL IPC never stalls MainActor / CGEventTap.
    private let audioQueue = DispatchQueue(label: "com.notchpulse.coreaudio", qos: .userInteractive)
    private let writeLock = NSLock()
    private struct PendingVolumeWrite {
        var volume: Float32
        var desiredMuted: Bool
        var generation: UInt64
    }
    private var pendingWrite: PendingVolumeWrite?
    private var isWriteWorkerScheduled = false
    private var latestCommandGeneration: UInt64 = 0

    // State owned exclusively by `audioQueue`.
    private var currentObservedDeviceID: AudioObjectID = kAudioObjectUnknown
    private var observedListenerDeviceIDs: Set<AudioObjectID> = []
    private var cachedWritableElements: [AudioObjectID: [UInt32]] = [:]
    private var cachedHasHardwareMute: [AudioObjectID: Bool] = [:]
    private var cachedHardwareMuted: Bool?
    private var previousVolumeBeforeMute: Float32 = 0.2
    private var softwareMuted: Bool = false
    private var pendingFetchWorkItem: DispatchWorkItem?

    private override init() {
        super.init()
        audioQueue.async { [weak self] in
            self?.setupAudioListenerOnQueue()
        }
    }

    var shouldShowOverlay: Bool { Date().timeIntervalSince(lastChangeAt) < visibleDuration }

    // MARK: - Public Control API
    @MainActor func increase(stepDivisor: Float = 1.0) {
        let divisor = max(stepDivisor, 0.25)
        let delta = step / Float32(divisor)
        let current = rawVolume
        let target = max(0, min(1, current + delta))
        setAbsolute(target)
        NotchPulseViewCoordinator.shared.toggleSneakPeek(status: true, type: .volume, value: CGFloat(target))
    }

    @MainActor func decrease(stepDivisor: Float = 1.0) {
        let divisor = max(stepDivisor, 0.25)
        let delta = step / Float32(divisor)
        let current = rawVolume
        let target = max(0, min(1, current - delta))
        setAbsolute(target)
        NotchPulseViewCoordinator.shared.toggleSneakPeek(status: true, type: .volume, value: CGFloat(target))
    }

    @MainActor func toggleMuteAction() {
        let willBeMuted = !isMuted
        let restoredVolume = rawVolume > 0.001 ? rawVolume : optimisticRestoreVolume
        if rawVolume > 0.001 {
            optimisticRestoreVolume = rawVolume
        }

        let targetVolume = willBeMuted ? rawVolume : restoredVolume
        publish(volume: targetVolume, muted: willBeMuted, touchDate: true)
        NotchPulseViewCoordinator.shared.toggleSneakPeek(
            status: true,
            type: .volume,
            value: CGFloat(willBeMuted ? 0 : restoredVolume)
        )

        writeLock.lock()
        latestCommandGeneration &+= 1
        let generation = latestCommandGeneration
        pendingWrite = nil
        writeLock.unlock()

        audioQueue.async { [weak self] in
            self?.performMuteToggleOnQueue(expectedGeneration: generation)
        }
    }

    func refresh() {
        audioQueue.async { [weak self] in
            self?.fetchCurrentVolumeOnQueue(isDeviceSwitch: false)
        }
    }

    func adjustRelative(delta: Float32) {
        let work: @MainActor () -> Void = {
            let target = max(0, min(1, self.rawVolume + delta))
            self.setAbsolute(target)
        }
        if Thread.isMainThread {
            MainActor.assumeIsolated(work)
        } else {
            Task { @MainActor in
                work()
            }
        }
    }

    @MainActor func setAbsolute(_ value: Float32) {
        let clamped = max(0, min(1, value))
        let shouldBeMuted = (clamped == 0)
        if clamped > 0.001 {
            optimisticRestoreVolume = clamped
        }

        publish(volume: clamped, muted: shouldBeMuted, touchDate: true)

        writeLock.lock()
        latestCommandGeneration &+= 1
        let generation = latestCommandGeneration
        pendingWrite = PendingVolumeWrite(
            volume: clamped,
            desiredMuted: shouldBeMuted,
            generation: generation
        )
        let shouldStartWorker = !isWriteWorkerScheduled
        if shouldStartWorker {
            isWriteWorkerScheduled = true
        }
        writeLock.unlock()

        if shouldStartWorker {
            audioQueue.async { [weak self] in
                self?.drainPendingWritesOnQueue()
            }
        }
    }

    private func currentGeneration() -> UInt64 {
        writeLock.lock()
        defer { writeLock.unlock() }
        return latestCommandGeneration
    }

    private func hasPendingOrActiveWrite() -> Bool {
        writeLock.lock()
        defer { writeLock.unlock() }
        return pendingWrite != nil || isWriteWorkerScheduled
    }

    // MARK: - Coalesced CoreAudio Write Worker (`audioQueue`)
    private func drainPendingWritesOnQueue() {
        while true {
            writeLock.lock()
            guard let next = pendingWrite else {
                isWriteWorkerScheduled = false
                writeLock.unlock()
                return
            }
            pendingWrite = nil
            writeLock.unlock()

            let deviceID = activeOutputDeviceIDOnQueue()
            guard deviceID != kAudioObjectUnknown else { continue }

            if !next.desiredMuted {
                if cachedHardwareMuted != false {
                    if isMutedOnDevice(deviceID) {
                        _ = setMuteOnDevice(deviceID, muted: false)
                    }
                    cachedHardwareMuted = false
                }
                if writeVolumeOnDevice(deviceID, value: next.volume) {
                    softwareMuted = false
                    if next.volume > 0.001 {
                        previousVolumeBeforeMute = next.volume
                    }
                }
            } else {
                _ = writeVolumeOnDevice(deviceID, value: 0)
                if cachedHardwareMuted != true {
                    if !isMutedOnDevice(deviceID) {
                        _ = setMuteOnDevice(deviceID, muted: true)
                    }
                    cachedHardwareMuted = true
                }
            }
        }
    }

    private func performMuteToggleOnQueue(expectedGeneration: UInt64) {
        let deviceID = activeOutputDeviceIDOnQueue()
        guard deviceID != kAudioObjectUnknown else {
            performSoftwareMuteToggleOnQueue(deviceID: deviceID, expectedGeneration: expectedGeneration)
            return
        }

        if hasHardwareMuteOnDevice(deviceID), let currentlyMuted = readMuteProperty(deviceID: deviceID) {
            let newMuted = !currentlyMuted
            if setMuteProperty(deviceID: deviceID, muted: newMuted) {
                cachedHardwareMuted = newMuted
                let vol = readVolumeOnDevice(deviceID) ?? previousVolumeBeforeMute
                if !newMuted && vol > 0.001 {
                    previousVolumeBeforeMute = vol
                }
                DispatchQueue.main.async {
                    guard self.currentGeneration() == expectedGeneration else { return }
                    self.publish(volume: vol, muted: newMuted, touchDate: true)
                }
                return
            }
        }

        performSoftwareMuteToggleOnQueue(deviceID: deviceID, expectedGeneration: expectedGeneration)
    }

    private func performSoftwareMuteToggleOnQueue(deviceID: AudioObjectID, expectedGeneration: UInt64) {
        if softwareMuted {
            let restore = max(0, min(1, previousVolumeBeforeMute))
            if deviceID != kAudioObjectUnknown {
                _ = writeVolumeOnDevice(deviceID, value: restore)
            }
            softwareMuted = false
            cachedHardwareMuted = false
            DispatchQueue.main.async {
                guard self.currentGeneration() == expectedGeneration else { return }
                self.publish(volume: restore, muted: false, touchDate: true)
            }
        } else {
            let currentVol = deviceID != kAudioObjectUnknown ? (readVolumeOnDevice(deviceID) ?? previousVolumeBeforeMute) : previousVolumeBeforeMute
            if currentVol > 0.001 {
                previousVolumeBeforeMute = currentVol
            }
            if deviceID != kAudioObjectUnknown {
                _ = writeVolumeOnDevice(deviceID, value: 0)
            }
            softwareMuted = true
            cachedHardwareMuted = true
            DispatchQueue.main.async {
                guard self.currentGeneration() == expectedGeneration else { return }
                self.publish(volume: 0, muted: true, touchDate: true)
            }
        }
    }

    // MARK: - CoreAudio Helpers (`audioQueue`)
    private func activeOutputDeviceIDOnQueue() -> AudioObjectID {
        if currentObservedDeviceID != kAudioObjectUnknown {
            return currentObservedDeviceID
        }
        let queried = systemOutputDeviceIDOnQueue()
        if queried != kAudioObjectUnknown {
            currentObservedDeviceID = queried
        }
        return queried
    }

    private func systemOutputDeviceIDOnQueue() -> AudioObjectID {
        var defaultDeviceID = kAudioObjectUnknown
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &defaultDeviceID
        )
        if status != noErr { return kAudioObjectUnknown }
        return defaultDeviceID
    }

    private func scheduleDebouncedFetchOnQueue() {
        pendingFetchWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.fetchCurrentVolumeOnQueue(isDeviceSwitch: false)
        }
        pendingFetchWorkItem = item
        audioQueue.asyncAfter(deadline: .now() + .milliseconds(15), execute: item)
    }

    private func fetchCurrentVolumeOnQueue(isDeviceSwitch: Bool) {
        if !isDeviceSwitch && hasPendingOrActiveWrite() {
            return
        }

        let deviceID = activeOutputDeviceIDOnQueue()
        guard deviceID != kAudioObjectUnknown else { return }

        let avg = readVolumeOnDevice(deviceID)
        let hardwareMuted = hasHardwareMuteOnDevice(deviceID) ? readMuteProperty(deviceID: deviceID) : nil
        if let hardwareMuted {
            cachedHardwareMuted = hardwareMuted
        }
        if let avg, avg > 0.001 {
            previousVolumeBeforeMute = avg
        }

        DispatchQueue.main.async {
            if isDeviceSwitch {
                self.lastDeviceSwitchAt = Date()
            }
            let writeActive = self.hasPendingOrActiveWrite()
            let isInitialFetch = !self.didInitialFetch
            let isRecentLocalChange = writeActive || (Date().timeIntervalSince(self.lastChangeAt) < 0.6)
            let isRecentDeviceSwitch = Date().timeIntervalSince(self.lastDeviceSwitchAt) < 2.0

            if let avg {
                if self.rawVolume != avg {
                    if !isInitialFetch && !isRecentLocalChange && !isRecentDeviceSwitch && !isDeviceSwitch {
                        self.lastChangeAt = Date()
                        NotchPulseViewCoordinator.shared.toggleSneakPeek(
                            status: true,
                            type: .volume,
                            value: CGFloat(avg)
                        )
                    }
                }
                if !isRecentLocalChange || isInitialFetch {
                    self.rawVolume = avg
                    if avg > 0.001 {
                        self.optimisticRestoreVolume = avg
                    }
                }
                self.didInitialFetch = true
            }

            if let hardwareMuted {
                if !isRecentLocalChange || isDeviceSwitch || isInitialFetch {
                    if self.isMuted != hardwareMuted && !isInitialFetch && !isDeviceSwitch {
                        self.lastChangeAt = Date()
                    }
                    self.isMuted = hardwareMuted
                }
            }
        }
    }

    private func setupAudioListenerOnQueue() {
        var defaultDevAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &defaultDevAddr, audioQueue
        ) { [weak self] _, _ in
            self?.rebindDeviceListenersOnQueue(forceFetch: true)
        }

        rebindDeviceListenersOnQueue(forceFetch: true)
    }

    private func rebindDeviceListenersOnQueue(forceFetch: Bool) {
        let deviceID = systemOutputDeviceIDOnQueue()
        guard deviceID != kAudioObjectUnknown else { return }

        let switchedDevice = (deviceID != currentObservedDeviceID)
        guard switchedDevice else {
            if forceFetch {
                scheduleDebouncedFetchOnQueue()
            }
            return
        }

        currentObservedDeviceID = deviceID
        cachedHardwareMuted = nil

        if !observedListenerDeviceIDs.contains(deviceID) {
            observedListenerDeviceIDs.insert(deviceID)

            var masterAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            if AudioObjectHasProperty(deviceID, &masterAddr) {
                AudioObjectAddPropertyListenerBlock(deviceID, &masterAddr, audioQueue) { [weak self] _, _ in
                    self?.scheduleDebouncedFetchOnQueue()
                }
            } else {
                for ch in [UInt32(1), UInt32(2)] {
                    var chAddr = AudioObjectPropertyAddress(
                        mSelector: kAudioDevicePropertyVolumeScalar,
                        mScope: kAudioDevicePropertyScopeOutput,
                        mElement: ch
                    )
                    if AudioObjectHasProperty(deviceID, &chAddr) {
                        AudioObjectAddPropertyListenerBlock(deviceID, &chAddr, audioQueue) { [weak self] _, _ in
                            self?.scheduleDebouncedFetchOnQueue()
                        }
                    }
                }
            }

            var muteAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            if AudioObjectHasProperty(deviceID, &muteAddr) {
                AudioObjectAddPropertyListenerBlock(deviceID, &muteAddr, audioQueue) { [weak self] _, _ in
                    self?.scheduleDebouncedFetchOnQueue()
                }
            }
        }

        // Pre-probe device capabilities off MainActor so the first keypress writes directly with zero probing overhead.
        _ = writableElementsOnDevice(deviceID)
        _ = hasHardwareMuteOnDevice(deviceID)
        fetchCurrentVolumeOnQueue(isDeviceSwitch: true)
    }

    private func readVolumeOnDevice(_ deviceID: AudioObjectID) -> Float32? {
        guard deviceID != kAudioObjectUnknown else { return nil }
        var collected: [Float32] = []
        for el in [kAudioObjectPropertyElementMain, 1, 2, 3, 4] {
            if let v = readValidatedScalar(deviceID: deviceID, element: el) {
                collected.append(max(0, min(1, v)))
            }
        }
        guard !collected.isEmpty else { return nil }
        return collected.reduce(0, +) / Float32(collected.count)
    }

    private func writableElementsOnDevice(_ deviceID: AudioObjectID) -> [UInt32] {
        if let cached = cachedWritableElements[deviceID] {
            return cached
        }
        let detected = detectWritableElements(deviceID: deviceID)
        cachedWritableElements[deviceID] = detected
        return detected
    }

    private func detectWritableElements(deviceID: AudioObjectID) -> [UInt32] {
        if isScalarPropertyAvailable(deviceID: deviceID, element: kAudioObjectPropertyElementMain) {
            return [kAudioObjectPropertyElementMain]
        }
        return [UInt32](1...4).filter { isScalarPropertyAvailable(deviceID: deviceID, element: $0) }
    }

    private func isScalarPropertyAvailable(deviceID: AudioObjectID, element: UInt32) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
        guard AudioObjectHasProperty(deviceID, &addr) else { return false }
        var isSettable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(deviceID, &addr, &isSettable) == noErr, isSettable.boolValue else {
            return false
        }
        var sizeNeeded: UInt32 = 0
        return AudioObjectGetPropertyDataSize(deviceID, &addr, 0, nil, &sizeNeeded) == noErr
            && sizeNeeded == UInt32(MemoryLayout<Float32>.size)
    }

    private func writeVolumeOnDevice(_ deviceID: AudioObjectID, value: Float32) -> Bool {
        guard deviceID != kAudioObjectUnknown else { return false }
        let newVal = max(0, min(1, value))
        let elements = writableElementsOnDevice(deviceID)
        guard !elements.isEmpty else { return false }

        var anyWritten = false
        for element in elements {
            if writeScalarFast(deviceID: deviceID, element: element, value: newVal) {
                anyWritten = true
            }
        }

        if !anyWritten {
            // Device configuration may have shifted; re-probe once and retry.
            cachedWritableElements.removeValue(forKey: deviceID)
            for element in writableElementsOnDevice(deviceID) {
                if writeScalarFast(deviceID: deviceID, element: element, value: newVal) {
                    anyWritten = true
                }
            }
        }
        return anyWritten
    }

    private func hasHardwareMuteOnDevice(_ deviceID: AudioObjectID) -> Bool {
        if let cached = cachedHasHardwareMute[deviceID] {
            return cached
        }
        var muteAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var sizeNeeded: UInt32 = 0
        let supported = AudioObjectHasProperty(deviceID, &muteAddr)
            && AudioObjectGetPropertyDataSize(deviceID, &muteAddr, 0, nil, &sizeNeeded) == noErr
            && sizeNeeded == UInt32(MemoryLayout<UInt32>.size)
        cachedHasHardwareMute[deviceID] = supported
        return supported
    }

    private func readMuteProperty(deviceID: AudioObjectID) -> Bool? {
        var muteAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &muteAddr, 0, nil, &size, &muted)
        return status == noErr ? (muted != 0) : nil
    }

    private func setMuteProperty(deviceID: AudioObjectID, muted: Bool) -> Bool {
        var muteAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var newVal: UInt32 = muted ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectSetPropertyData(deviceID, &muteAddr, 0, nil, size, &newVal) == noErr
    }

    private func isMutedOnDevice(_ deviceID: AudioObjectID) -> Bool {
        if hasHardwareMuteOnDevice(deviceID), let muted = readMuteProperty(deviceID: deviceID) {
            return muted
        }
        return softwareMuted
    }

    @discardableResult
    private func setMuteOnDevice(_ deviceID: AudioObjectID, muted: Bool) -> Bool {
        if hasHardwareMuteOnDevice(deviceID) {
            return setMuteProperty(deviceID: deviceID, muted: muted)
        }
        return false
    }

    private func readValidatedScalar(deviceID: AudioObjectID, element: UInt32) -> Float32? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
        guard AudioObjectHasProperty(deviceID, &addr) else { return nil }
        var sizeNeeded: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &addr, 0, nil, &sizeNeeded) == noErr,
            sizeNeeded == UInt32(MemoryLayout<Float32>.size)
        else { return nil }
        var vol = Float32(0)
        var size = sizeNeeded
        let status = AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &vol)
        return status == noErr ? vol : nil
    }

    private func writeScalarFast(deviceID: AudioObjectID, element: UInt32, value: Float32) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
        var val = value
        return AudioObjectSetPropertyData(
            deviceID, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &val
        ) == noErr
    }

    private func publish(volume: Float32, muted: Bool, touchDate: Bool) {
        let update = {
            if touchDate { self.lastChangeAt = Date() }
            self.rawVolume = volume
            self.isMuted = muted
        }
        if Thread.isMainThread {
            update()
        } else {
            DispatchQueue.main.async(execute: update)
        }
    }
}

extension Array where Element == Float32 {
    fileprivate var average: Float32? { isEmpty ? nil : reduce(0, +) / Float32(count) }
}


