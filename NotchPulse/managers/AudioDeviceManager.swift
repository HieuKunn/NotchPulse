import AppKit
import Combine
import CoreAudio
import Defaults
import Foundation

enum AudioDeviceType: String, Equatable {
    case builtinSpeaker
    case headphones
    case airpods
    case display
    case usb
    case bluetooth
    case microphone
    case unknown
}

struct AudioDeviceItem: Identifiable, Equatable {
    let id: AudioObjectID
    let uid: String
    let name: String
    let isInput: Bool
    let isOutput: Bool
    var isDefault: Bool
    var volume: Float // 0.0 - 1.0
    var isMuted: Bool
    var deviceType: AudioDeviceType
    var iconName: String
    var batteryLevel: Int? = nil
    
    static func == (lhs: AudioDeviceItem, rhs: AudioDeviceItem) -> Bool {
        lhs.id == rhs.id &&
        lhs.isDefault == rhs.isDefault &&
        abs(lhs.volume - rhs.volume) < 0.002 &&
        lhs.isMuted == rhs.isMuted &&
        lhs.name == rhs.name &&
        lhs.batteryLevel == rhs.batteryLevel
    }
}

enum AudioHubTab: String, CaseIterable {
    case output = "Output"
    case input = "Input"
}

@MainActor
final class AudioDeviceManager: ObservableObject {
    static let shared = AudioDeviceManager()

    @Published var selectedTab: AudioHubTab = .output
    @Published var outputDevices: [AudioDeviceItem] = []
    @Published var inputDevices: [AudioDeviceItem] = []
    @Published var defaultOutputDevice: AudioDeviceItem?
    @Published var defaultInputDevice: AudioDeviceItem?

    private var deviceSavedVolumes: [String: Float] = [:] {
        didSet {
            UserDefaults.standard.set(deviceSavedVolumes, forKey: "NotchPulse_DeviceSavedVolumes")
        }
    }

    private var cancellables = Set<AnyCancellable>()

    private init() {
        if let savedDevVols = UserDefaults.standard.dictionary(forKey: "NotchPulse_DeviceSavedVolumes") as? [String: Float] {
            self.deviceSavedVolumes = savedDevVols
        }

        refreshDevices()
        setupListeners()
        setupVolumeSync()
    }

    // MARK: - CoreAudio Device Refreshing

    func refreshDevices() {
        let allIDs = getAllAudioDeviceIDs()
        let defaultOutID = getDefaultDeviceID(isInput: false)
        let defaultInID = getDefaultDeviceID(isInput: true)

        var newOutputs: [AudioDeviceItem] = []
        var newInputs: [AudioDeviceItem] = []

        for id in allIDs {
            guard let name = getDeviceName(id), !name.isEmpty else { continue }
            let uid = getDeviceUID(id) ?? "\(id)"
            let hasOutput = deviceHasStreams(id, isInput: false)
            let hasInput = deviceHasStreams(id, isInput: true)
            let transport = getTransportType(id)

            if hasOutput {
                let isDef = (id == defaultOutID)
                var vol = getDeviceVolume(id, isInput: false)
                var muted = getDeviceMute(id, isInput: false)
                if isDef {
                    let activeVol = VolumeManager.shared.rawVolume
                    if activeVol > 0 || VolumeManager.shared.isMuted {
                        vol = activeVol
                        muted = VolumeManager.shared.isMuted
                    }
                }
                let type = resolveDeviceType(name: name, transport: transport, isInput: false)
                let icon = iconForType(type, isInput: false)
                let battery = (type == .airpods || type == .headphones || type == .bluetooth) ?
                    BluetoothHeadphoneManager.shared.getBatteryPercentage(forDeviceNamed: name) : nil

                let item = AudioDeviceItem(
                    id: id,
                    uid: uid,
                    name: name,
                    isInput: false,
                    isOutput: true,
                    isDefault: isDef,
                    volume: vol,
                    isMuted: muted,
                    deviceType: type,
                    iconName: icon,
                    batteryLevel: battery
                )
                newOutputs.append(item)
                if isDef {
                    self.defaultOutputDevice = item
                }
            }

            if hasInput {
                let isDef = (id == defaultInID)
                let vol = getDeviceVolume(id, isInput: true)
                let muted = getDeviceMute(id, isInput: true)
                let type = resolveDeviceType(name: name, transport: transport, isInput: true)
                let icon = iconForType(type, isInput: true)
                let battery = (type == .airpods || type == .headphones || type == .bluetooth) ?
                    BluetoothHeadphoneManager.shared.getBatteryPercentage(forDeviceNamed: name) : nil

                let item = AudioDeviceItem(
                    id: id,
                    uid: uid,
                    name: name,
                    isInput: true,
                    isOutput: false,
                    isDefault: isDef,
                    volume: vol,
                    isMuted: muted,
                    deviceType: type,
                    iconName: icon,
                    batteryLevel: battery
                )
                newInputs.append(item)
                if isDef {
                    self.defaultInputDevice = item
                }
            }
        }

        self.outputDevices = newOutputs
        self.inputDevices = newInputs
    }

    // MARK: - Actions

    func setDefaultDevice(id: AudioObjectID, isInput: Bool) {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: isInput ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var devID = id
        let size = UInt32(MemoryLayout<AudioObjectID>.size)
        _ = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, size, &devID)
        
        if !isInput {
            var sysAddr = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            _ = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &sysAddr, 0, nil, size, &devID)
        }

        // Optimistically update device selection immediately in UI
        if isInput {
            var updated = inputDevices
            for i in 0..<updated.count {
                let match = (updated[i].id == id)
                updated[i].isDefault = match
                if match {
                    self.defaultInputDevice = updated[i]
                }
            }
            self.inputDevices = updated
        } else {
            var updated = outputDevices
            for i in 0..<updated.count {
                let match = (updated[i].id == id)
                updated[i].isDefault = match
                if match {
                    let targetDev = updated[i]
                    let targetVol = deviceSavedVolumes[targetDev.uid] ?? targetDev.volume
                    updated[i].volume = targetVol
                    self.defaultOutputDevice = updated[i]
                }
            }
            self.outputDevices = updated
            if let def = self.defaultOutputDevice {
                setDeviceVolume(id: def.id, volume: def.volume, isInput: false)
            }
        }

        // Schedule delayed refreshes to sync with CoreAudio HAL async switch
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.refreshDevices()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.refreshDevices()
        }
    }

    func setDeviceVolume(id: AudioObjectID, volume: Float, isInput: Bool) {
        let clamped = max(0, min(1, volume))
        let scope: AudioObjectPropertyScope = isInput ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput
        
        for element in [kAudioObjectPropertyElementMain, UInt32(1), UInt32(2)] {
            var addr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: scope,
                mElement: element
            )
            if AudioObjectHasProperty(id, &addr) {
                var val = clamped
                let size = UInt32(MemoryLayout<Float32>.size)
                _ = AudioObjectSetPropertyData(id, &addr, 0, nil, size, &val)
            }
        }

        // Optimistically update list & default devices
        if isInput {
            if let idx = inputDevices.firstIndex(where: { $0.id == id }) {
                inputDevices[idx].volume = clamped
                deviceSavedVolumes[inputDevices[idx].uid] = clamped
            }
            if defaultInputDevice?.id == id {
                defaultInputDevice?.volume = clamped
            }
        } else {
            if let idx = outputDevices.firstIndex(where: { $0.id == id }) {
                outputDevices[idx].volume = clamped
                deviceSavedVolumes[outputDevices[idx].uid] = clamped
            }
            if defaultOutputDevice?.id == id {
                defaultOutputDevice?.volume = clamped
                VolumeManager.shared.setAbsolute(clamped)
                NotchPulseViewCoordinator.shared.toggleSneakPeek(status: true, type: .volume, value: CGFloat(clamped))
            }
        }
    }

    func toggleDeviceMute(id: AudioObjectID, isInput: Bool) {
        let scope: AudioObjectPropertyScope = isInput ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )

        if AudioObjectHasProperty(id, &addr) {
            var muted: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &muted) == noErr {
                var newMute = (muted == 0) ? UInt32(1) : UInt32(0)
                _ = AudioObjectSetPropertyData(id, &addr, 0, nil, size, &newMute)
            }
        }

        if isInput {
            if let idx = inputDevices.firstIndex(where: { $0.id == id }) {
                inputDevices[idx].isMuted.toggle()
            }
        } else {
            if let idx = outputDevices.firstIndex(where: { $0.id == id }) {
                outputDevices[idx].isMuted.toggle()
            }
            if let defOut = defaultOutputDevice, defOut.id == id {
                VolumeManager.shared.toggleMuteAction()
            }
        }
    }

    // MARK: - CoreAudio Internal Queries

    private func getAllAudioDeviceIDs() -> [AudioObjectID] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize) == noErr else {
            return []
        }

        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var deviceIDs = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize, &deviceIDs) == noErr else {
            return []
        }
        return deviceIDs
    }

    private func getDefaultDeviceID(isInput: Bool) -> AudioObjectID {
        var devID = kAudioObjectUnknown
        var addr = AudioObjectPropertyAddress(
            mSelector: isInput ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        _ = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &devID)
        return devID
    }

    private func getDeviceName(_ id: AudioObjectID) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &name) == noErr else {
            return nil
        }
        return name as String
    }

    private func getDeviceUID(_ id: AudioObjectID) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uid: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &uid) == noErr else {
            return nil
        }
        return uid as String
    }

    private func deviceHasStreams(_ id: AudioObjectID, isInput: Bool) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: isInput ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr else {
            return false
        }
        return size > 0
    }

    private func getTransportType(_ id: AudioObjectID) -> UInt32 {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        _ = AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &transport)
        return transport
    }

    private func getDeviceVolume(_ id: AudioObjectID, isInput: Bool) -> Float {
        let scope: AudioObjectPropertyScope = isInput ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput
        var volumes: [Float] = []
        for element in [kAudioObjectPropertyElementMain, UInt32(1), UInt32(2)] {
            var addr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: scope,
                mElement: element
            )
            if AudioObjectHasProperty(id, &addr) {
                var vol: Float32 = 0
                var size = UInt32(MemoryLayout<Float32>.size)
                if AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &vol) == noErr {
                    volumes.append(Float(vol))
                }
            }
        }
        if !volumes.isEmpty {
            return volumes.reduce(0, +) / Float(volumes.count)
        }
        if let uid = getDeviceUID(id), let saved = deviceSavedVolumes[uid] {
            return saved
        }
        return 1.0
    }

    private func getDeviceMute(_ id: AudioObjectID, isInput: Bool) -> Bool {
        let scope: AudioObjectPropertyScope = isInput ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectHasProperty(id, &addr) {
            var muted: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &muted) == noErr {
                return muted != 0
            }
        }
        return false
    }

    private func resolveDeviceType(name: String, transport: UInt32, isInput: Bool) -> AudioDeviceType {
        let lower = name.lowercased()
        if lower.contains("airpod") {
            return .airpods
        }
        if lower.contains("headphone") || lower.contains("headset") || lower.contains("earphone") {
            return .headphones
        }
        if lower.contains("display") || lower.contains("hdmi") || lower.contains("tv") || lower.contains("qs2") || lower.contains("monitor") {
            return .display
        }
        if transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE {
            return .bluetooth
        }
        if transport == kAudioDeviceTransportTypeUSB || lower.contains("usb") {
            return .usb
        }
        if isInput {
            return .microphone
        }
        return .builtinSpeaker
    }

    private func iconForType(_ type: AudioDeviceType, isInput: Bool) -> String {
        switch type {
        case .builtinSpeaker:
            return "laptopcomputer"
        case .headphones:
            return "headphones"
        case .airpods:
            return "airpodspro"
        case .display:
            return "display"
        case .usb:
            return isInput ? "mic.fill" : "cable.connector"
        case .bluetooth:
            return isInput ? "mic" : "headphones"
        case .microphone:
            return "mic.fill"
        case .unknown:
            return isInput ? "mic" : "speaker.wave.2"
        }
    }

    private func setupListeners() {
        let systemObjectID = AudioObjectID(kAudioObjectSystemObject)

        // 1. Devices list changed
        var devAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(systemObjectID, &devAddr, nil) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.refreshDevices()
            }
        }

        // 2. Default Output changed
        var outAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(systemObjectID, &outAddr, nil) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.refreshDevices()
            }
        }

        // 3. Default Input changed
        var inAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(systemObjectID, &inAddr, nil) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.refreshDevices()
            }
        }
    }

    private func setupVolumeSync() {
        VolumeManager.shared.$rawVolume
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newVol in
                guard let self = self else { return }
                guard let defaultID = self.defaultOutputDevice?.id else { return }

                if let idx = self.outputDevices.firstIndex(where: { $0.id == defaultID }) {
                    if abs(self.outputDevices[idx].volume - newVol) > 0.002 {
                        self.outputDevices[idx].volume = newVol
                        self.deviceSavedVolumes[self.outputDevices[idx].uid] = newVol
                    }
                }
                if let def = self.defaultOutputDevice, abs(def.volume - newVol) > 0.002 {
                    self.defaultOutputDevice?.volume = newVol
                }
            }
            .store(in: &cancellables)

        VolumeManager.shared.$isMuted
            .receive(on: DispatchQueue.main)
            .sink { [weak self] muted in
                guard let self = self else { return }
                guard let defaultID = self.defaultOutputDevice?.id else { return }

                if let idx = self.outputDevices.firstIndex(where: { $0.id == defaultID }) {
                    if self.outputDevices[idx].isMuted != muted {
                        self.outputDevices[idx].isMuted = muted
                    }
                }
                if self.defaultOutputDevice?.isMuted != muted {
                    self.defaultOutputDevice?.isMuted = muted
                }
            }
            .store(in: &cancellables)
    }
}
