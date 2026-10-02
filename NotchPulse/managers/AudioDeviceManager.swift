//
//  AudioDeviceManager.swift
//  NotchPulse
//
//  Created by Alexander on 2026-10-02.
//

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
    
    static func == (lhs: AudioDeviceItem, rhs: AudioDeviceItem) -> Bool {
        lhs.id == rhs.id &&
        lhs.isDefault == rhs.isDefault &&
        abs(lhs.volume - rhs.volume) < 0.01 &&
        lhs.isMuted == rhs.isMuted &&
        lhs.name == rhs.name
    }
}

struct AudioAppItem: Identifiable, Equatable {
    let id: String // bundleIdentifier or process name
    let name: String
    let bundleIdentifier: String?
    var volume: Float // 0.0 - 1.0
    var isMuted: Bool
    var isPlaying: Bool
    
    var icon: NSImage {
        if let bundleId = bundleIdentifier,
           let appUrl = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            return NSWorkspace.shared.icon(forFile: appUrl.path)
        }
        return NSWorkspace.shared.icon(for: .application)
    }
    
    static func == (lhs: AudioAppItem, rhs: AudioAppItem) -> Bool {
        lhs.id == rhs.id &&
        abs(lhs.volume - rhs.volume) < 0.01 &&
        lhs.isMuted == rhs.isMuted &&
        lhs.isPlaying == rhs.isPlaying
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
    @Published var activeApps: [AudioAppItem] = []
    @Published var defaultOutputDevice: AudioDeviceItem?
    @Published var defaultInputDevice: AudioDeviceItem?

    private var appVolumes: [String: Float] = [:] {
        didSet {
            UserDefaults.standard.set(appVolumes, forKey: "NotchPulse_AppVolumes")
        }
    }
    
    private var appMutes: [String: Bool] = [:] {
        didSet {
            UserDefaults.standard.set(appMutes, forKey: "NotchPulse_AppMutes")
        }
    }

    private var deviceSavedVolumes: [String: Float] = [:] {
        didSet {
            UserDefaults.standard.set(deviceSavedVolumes, forKey: "NotchPulse_DeviceSavedVolumes")
        }
    }

    private var cancellables = Set<AnyCancellable>()
    private var hardwareListenerBlock: AudioObjectPropertyListenerBlock?

    private init() {
        if let savedVols = UserDefaults.standard.dictionary(forKey: "NotchPulse_AppVolumes") as? [String: Float] {
            self.appVolumes = savedVols
        }
        if let savedMutes = UserDefaults.standard.dictionary(forKey: "NotchPulse_AppMutes") as? [String: Bool] {
            self.appMutes = savedMutes
        }
        if let savedDevVols = UserDefaults.standard.dictionary(forKey: "NotchPulse_DeviceSavedVolumes") as? [String: Float] {
            self.deviceSavedVolumes = savedDevVols
        }

        refreshDevices()
        refreshApps()
        setupListeners()
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
                let vol = getDeviceVolume(id, isInput: false)
                let muted = getDeviceMute(id, isInput: false)
                let type = resolveDeviceType(name: name, transport: transport, isInput: false)
                let icon = iconForType(type, isInput: false)

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
                    iconName: icon
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
                    iconName: icon
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

    // MARK: - CoreAudio Process & Media Detection (FineTune-grade Engine)

    private var processListenerBlocks: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
    private var monitoredProcesses: Set<AudioObjectID> = []

    private typealias ResponsibilityFunc = @convention(c) (pid_t) -> pid_t

    private func getResponsiblePID(for pid: pid_t) -> pid_t? {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -1), "responsibility_get_pid_responsible_for_pid") else {
            return nil
        }
        let responsiblePID = unsafeBitCast(symbol, to: ResponsibilityFunc.self)(pid)
        return responsiblePID > 0 && responsiblePID != pid ? responsiblePID : nil
    }

    private func findResponsibleApp(
        for pid: pid_t,
        in runningAppsByPID: [pid_t: NSRunningApplication]
    ) -> NSRunningApplication? {
        if let responsiblePID = getResponsiblePID(for: pid),
           let app = runningAppsByPID[responsiblePID],
           app.bundleURL?.pathExtension == "app" {
            return app
        }

        var currentPID = pid
        var visited = Set<pid_t>()

        while currentPID > 1 && !visited.contains(currentPID) {
            visited.insert(currentPID)

            if let app = runningAppsByPID[currentPID],
               app.bundleURL?.pathExtension == "app" {
                return app
            }

            var info = kinfo_proc()
            var size = MemoryLayout<kinfo_proc>.size
            var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, currentPID]

            guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { break }

            let parentPID = info.kp_eproc.e_ppid
            if parentPID == currentPID { break }
            currentPID = parentPID
        }

        return nil
    }

    private static let systemDaemonPrefixes: [String] = [
        "com.apple.siri", "com.apple.Siri", "com.apple.assistant", "com.apple.audio",
        "com.apple.coreaudio", "com.apple.mediaremote", "com.apple.accessibility.heard",
        "com.apple.hearingd", "com.apple.voicebankingd", "com.apple.systemsound",
        "com.apple.FrontBoardServices", "com.apple.frontboard", "com.apple.springboard",
        "com.apple.notificationcenter", "com.apple.NotificationCenter", "com.apple.UserNotifications",
        "com.apple.usernotifications", "com.apple.SpeechRecognitionCore", "com.apple.speech",
        "com.apple.dictation", "com.apple.corespeech", "com.apple.CoreSpeech",
        "com.apple.VoiceControl", "com.apple.voicecontrol"
    ]

    private static let systemDaemonNames: [String] = [
        "systemsoundserverd", "systemsoundserv", "coreaudiod", "audiomxd",
        "speechrecognitiond", "dictationd", "corespeech"
    ]

    private func isSystemDaemon(bundleID: String?, name: String) -> Bool {
        if let bundleID = bundleID {
            if Self.systemDaemonPrefixes.contains(where: { bundleID.hasPrefix($0) }) {
                return true
            }
        }
        let lower = name.lowercased()
        if Self.systemDaemonNames.contains(where: { lower.hasPrefix($0) }) {
            return true
        }
        return false
    }

    private func readCoreAudioProcessIDs() -> [AudioObjectID] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &size) == noErr else {
            return []
        }
        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var ids = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &size, &ids) == noErr else {
            return []
        }
        return ids
    }

    private func readProcessPID(_ id: AudioObjectID) -> pid_t? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var pid: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        guard AudioObjectGetPropertyData(id, &propertyAddress, 0, nil, &size, &pid) == noErr else {
            return nil
        }
        return pid
    }

    private func readProcessIsRunning(_ id: AudioObjectID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunning,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &propertyAddress, 0, nil, &size, &running) == noErr else {
            return false
        }
        return running != 0
    }

    private func readProcessBundleID(_ id: AudioObjectID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyBundleID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var unmanaged: Unmanaged<CFString>? = nil
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let err = withUnsafeMutablePointer(to: &unmanaged) { ptr in
            AudioObjectGetPropertyData(id, &propertyAddress, 0, nil, &size, UnsafeMutableRawPointer(ptr))
        }
        guard err == noErr, let unmanaged = unmanaged else { return nil }
        return unmanaged.takeRetainedValue() as String
    }

    func refreshApps() {
        let running = NSWorkspace.shared.runningApplications
        let runningAppsByPID = Dictionary(
            running.map { ($0.processIdentifier, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        let myPID = ProcessInfo.processInfo.processIdentifier
        let myBid = Bundle.main.bundleIdentifier ?? ""
        let isSystemMusicPlaying = MusicManager.shared.isPlaying

        // 1. Query CoreAudio HAL active audio processes (identifies apps actually producing media/audio)
        let coreAudioProcessIDs = readCoreAudioProcessIDs()
        updateProcessListeners(for: coreAudioProcessIDs)

        var appsByPID: [pid_t: AudioAppItem] = [:]

        for objID in coreAudioProcessIDs {
            guard let pid = readProcessPID(objID), pid != myPID else { continue }
            guard readProcessIsRunning(objID) else { continue }

            let directApp = runningAppsByPID[pid]
            let isRealApp = directApp?.bundleURL?.pathExtension == "app"
            let resolvedApp = isRealApp ? directApp : findResponsibleApp(for: pid, in: runningAppsByPID)
            let parentPID = resolvedApp?.processIdentifier ?? pid

            let name = resolvedApp?.localizedName
                ?? readProcessBundleID(objID)?.components(separatedBy: ".").last
                ?? "Unknown"
            let bundleID = resolvedApp?.bundleIdentifier ?? readProcessBundleID(objID)

            if isSystemDaemon(bundleID: bundleID, name: name) { continue }

            let bid = bundleID ?? name
            if bid == myBid { continue }

            let savedVol = appVolumes[bid] ?? 1.0
            let savedMute = appMutes[bid] ?? false

            if appsByPID[parentPID] == nil {
                appsByPID[parentPID] = AudioAppItem(
                    id: bid,
                    name: name,
                    bundleIdentifier: bundleID,
                    volume: savedVol,
                    isMuted: savedMute,
                    isPlaying: true
                )
            }
        }

        // Also check if system Music or Spotify is playing
        if isSystemMusicPlaying {
            for (bid, fallbackName) in [("com.apple.Music", "Music"), ("com.spotify.client", "Spotify")] {
                if let app = running.first(where: { $0.bundleIdentifier == bid }) {
                    let pid = app.processIdentifier
                    if appsByPID[pid] == nil {
                        let savedVol = appVolumes[bid] ?? 1.0
                        let savedMute = appMutes[bid] ?? false
                        appsByPID[pid] = AudioAppItem(
                            id: bid,
                            name: app.localizedName ?? fallbackName,
                            bundleIdentifier: bid,
                            volume: savedVol,
                            isMuted: savedMute,
                            isPlaying: true
                        )
                    }
                }
            }
        }

        let sorted = appsByPID.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        self.activeApps = sorted
    }

    private func updateProcessListeners(for processIDs: [AudioObjectID]) {
        let currentSet = Set(processIDs)
        let removed = monitoredProcesses.subtracting(currentSet)
        for objectID in removed {
            if let block = processListenerBlocks.removeValue(forKey: objectID) {
                var address = AudioObjectPropertyAddress(
                    mSelector: kAudioProcessPropertyIsRunning,
                    mScope: kAudioObjectPropertyScopeGlobal,
                    mElement: kAudioObjectPropertyElementMain
                )
                AudioObjectRemovePropertyListenerBlock(objectID, &address, nil, block)
            }
        }

        let added = currentSet.subtracting(monitoredProcesses)
        for objectID in added {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyIsRunning,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    self?.refreshApps()
                }
            }
            if AudioObjectAddPropertyListenerBlock(objectID, &address, nil, block) == noErr {
                processListenerBlocks[objectID] = block
            }
        }
        monitoredProcesses = currentSet
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
                    self.defaultOutputDevice = updated[i]
                    let targetDev = updated[i]
                    // Auto-restore saved preferred volume for this device if previously saved
                    if let savedVol = deviceSavedVolumes[targetDev.uid] {
                        setDeviceVolume(id: targetDev.id, volume: savedVol, isInput: false)
                    } else {
                        let vol = targetDev.volume
                        VolumeManager.shared.setAbsolute(vol)
                        NotchPulseViewCoordinator.shared.toggleSneakPeek(status: true, type: .volume, value: CGFloat(vol))
                    }
                }
            }
            self.outputDevices = updated
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

    private var appVolumeTasks: [String: Task<Void, Never>] = [:]

    func setAppVolume(id: String, volume: Float) {
        let clamped = max(0, min(2.0, volume))
        appVolumes[id] = clamped
        if let idx = activeApps.firstIndex(where: { $0.id == id }) {
            activeApps[idx].volume = clamped
        }
        let isMuted = appMutes[id] ?? false
        
        let lower = id.lowercased()
        if (lower.contains("spotify") || lower.contains("music")) && MusicManager.shared.isPlaying {
            MusicManager.shared.setVolume(to: Double(clamped))
        }
        
        dispatchAppVolume(id: id, volume: clamped, isMuted: isMuted)
    }

    func toggleAppMute(id: String) {
        let current = appMutes[id] ?? false
        let newMute = !current
        appMutes[id] = newMute
        if let idx = activeApps.firstIndex(where: { $0.id == id }) {
            activeApps[idx].isMuted = newMute
        }
        let vol = appVolumes[id] ?? 1.0
        
        let lower = id.lowercased()
        if (lower.contains("spotify") || lower.contains("music")) && MusicManager.shared.isPlaying {
            MusicManager.shared.setVolume(to: newMute ? 0 : Double(vol))
        }
        
        dispatchAppVolume(id: id, volume: vol, isMuted: newMute)
    }

    private func dispatchAppVolume(id: String, volume: Float, isMuted: Bool) {
        appVolumeTasks[id]?.cancel()
        appVolumeTasks[id] = Task.detached(priority: .userInitiated) {
            // Debounce rapid slider dragging and mouse wheel scrolls (35ms)
            try? await Task.sleep(nanoseconds: 35_000_000)
            guard !Task.isCancelled else { return }
            AudioDeviceManager.applyVolumeToApp(id: id, volume: volume, isMuted: isMuted)
        }
    }

    nonisolated static func applyVolumeToApp(id: String, volume: Float, isMuted: Bool) {
        let lower = id.lowercased()
        let vol = isMuted ? 0.0 : Double(volume)
        let mutedBool = isMuted || (volume == 0)
        
        let jsSnippet = """
        (() => {
            const v = \(vol);
            const m = \(mutedBool);
            function adjustMedia(el) {
                if (!el) return;
                if (v > 1.0) {
                    el.volume = 1.0;
                    el.muted = m;
                    try {
                        if (!el._npGain) {
                            const ctx = new (window.AudioContext || window.webkitAudioContext)();
                            const src = ctx.createMediaElementSource(el);
                            const gain = ctx.createGain();
                            src.connect(gain);
                            gain.connect(ctx.destination);
                            el._npGain = gain;
                            el._npCtx = ctx;
                        }
                        if (el._npGain) {
                            el._npGain.gain.value = v;
                            if (el._npCtx && el._npCtx.state === 'suspended') { el._npCtx.resume(); }
                        }
                    } catch(err) {}
                } else {
                    el.volume = Math.max(0, Math.min(1, v));
                    el.muted = m;
                    if (el._npGain) { el._npGain.gain.value = 1.0; }
                }
            }
            try {
                const ytp = document.getElementById('movie_player') || document.querySelector('.html5-video-player');
                if (ytp && typeof ytp.setVolume === 'function') {
                    if (m) { ytp.mute(); } else { ytp.unMute(); ytp.setVolume(Math.min(100, v * 100)); }
                }
            } catch(err) {}
            document.querySelectorAll('video, audio').forEach(adjustMedia);
            document.querySelectorAll('*').forEach(el => {
                if (el.shadowRoot) {
                    el.shadowRoot.querySelectorAll('video, audio').forEach(adjustMedia);
                }
            });
            return true;
        })()
        """.replacingOccurrences(of: "\n", with: " ")

        var script: String?
        
        if lower.contains("spotify") {
            let spotifyVol = Int(vol * 100)
            script = """
            tell application "Spotify"
                if it is running then
                    set sound volume to \(spotifyVol)
                end if
            end tell
            """
        } else if lower.contains("music") || lower.contains("itunes") {
            let musicVol = Int(vol * 100)
            script = """
            tell application "Music"
                if it is running then
                    if \(mutedBool) then
                        set mute to true
                    else
                        set mute to false
                        set sound volume to \(musicVol)
                    end if
                end if
            end tell
            """
        } else if lower.contains("apple.tv") || lower == "tv" {
            let tvVol = Int(vol * 100)
            script = """
            tell application "TV"
                if it is running then
                    if \(mutedBool) then
                        set mute to true
                    else
                        set mute to false
                        set sound volume to \(tvVol)
                    end if
                end if
            end tell
            """
        } else if lower.contains("podcasts") {
            let podVol = Int(vol * 100)
            script = """
            tell application "Podcasts"
                if it is running then
                    set sound volume to \(podVol)
                end if
            end tell
            """
        } else if lower.contains("vlc") {
            let vlcVol = Int(vol * 256)
            script = """
            tell application "VLC"
                if it is running then
                    if \(mutedBool) then
                        mute
                    else
                        set audio volume to \(vlcVol)
                    end if
                end if
            end tell
            """
        } else if lower.contains("iina") {
            let iinaVol = Int(vol * 100)
            script = """
            tell application "IINA"
                if it is running then
                    set volume to \(iinaVol)
                end if
            end tell
            """
        } else if lower.contains("quicktime") {
            script = """
            tell application "QuickTime Player"
                if it is running then
                    repeat with d in documents
                        try
                            set audio volume of d to \(vol)
                        end try
                    end repeat
                end if
            end tell
            """
        } else if lower.contains("arc") {
            script = """
            tell application "Arc"
                if it is running then
                    with timeout of 2 seconds
                        repeat with w in windows
                            repeat with t in tabs of w
                                try
                                    tell t to execute javascript "\(jsSnippet)"
                                end try
                            end repeat
                        end repeat
                    end timeout
                end if
            end tell
            """
        } else if lower.contains("chrome") {
            script = """
            tell application "Google Chrome"
                if it is running then
                    with timeout of 2 seconds
                        repeat with w in windows
                            repeat with t in tabs of w
                                try
                                    tell t to execute javascript "\(jsSnippet)"
                                end try
                            end repeat
                        end repeat
                    end timeout
                end if
            end tell
            """
        } else if lower.contains("brave") {
            script = """
            tell application "Brave Browser"
                if it is running then
                    with timeout of 2 seconds
                        repeat with w in windows
                            repeat with t in tabs of w
                                try
                                    tell t to execute javascript "\(jsSnippet)"
                                end try
                            end repeat
                        end repeat
                    end timeout
                end if
            end tell
            """
        } else if lower.contains("edgemac") || lower.contains("microsoft edge") || lower.contains("edge") {
            script = """
            tell application "Microsoft Edge"
                if it is running then
                    with timeout of 2 seconds
                        repeat with w in windows
                            repeat with t in tabs of w
                                try
                                    tell t to execute javascript "\(jsSnippet)"
                                end try
                            end repeat
                        end repeat
                    end timeout
                end if
            end tell
            """
        } else if lower.contains("safari") {
            script = """
            tell application "Safari"
                if it is running then
                    with timeout of 2 seconds
                        repeat with w in windows
                            repeat with t in tabs of w
                                try
                                    tell t to do JavaScript "\(jsSnippet)"
                                end try
                            end repeat
                        end repeat
                    end timeout
                end if
            end tell
            """
        } else if lower.contains("orion") {
            script = """
            tell application "Orion"
                if it is running then
                    with timeout of 2 seconds
                        repeat with w in windows
                            repeat with t in tabs of w
                                try
                                    tell t to do JavaScript "\(jsSnippet)"
                                end try
                            end repeat
                        end repeat
                    end timeout
                end if
            end tell
            """
        } else if lower.contains("opera") {
            script = """
            tell application "Opera"
                if it is running then
                    with timeout of 2 seconds
                        repeat with w in windows
                            repeat with t in tabs of w
                                try
                                    tell t to execute javascript "\(jsSnippet)"
                                end try
                            end repeat
                        end repeat
                    end timeout
                end if
            end tell
            """
        } else if lower.contains("vivaldi") {
            script = """
            tell application "Vivaldi"
                if it is running then
                    with timeout of 2 seconds
                        repeat with w in windows
                            repeat with t in tabs of w
                                try
                                    tell t to execute javascript "\(jsSnippet)"
                                end try
                            end repeat
                        end repeat
                    end timeout
                end if
            end tell
            """
        }
        
        if let script = script {
            var error: NSDictionary?
            if let appleScript = NSAppleScript(source: script) {
                appleScript.executeAndReturnError(&error)
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

        // 4. CoreAudio Process Object list changed (real-time detection when apps start/stop playing media)
        var procAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(systemObjectID, &procAddr, nil) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.refreshApps()
            }
        }

        // Listen for workspace app lifecycle to update apps list
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refreshApps()
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refreshApps()
        }

        // Listen for Universal Audio Engine toggle changes
        Defaults.observe(.enableVirtualAudioDriver) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshApps()
            }
        }.tieToLifetime(of: self)
    }
}
