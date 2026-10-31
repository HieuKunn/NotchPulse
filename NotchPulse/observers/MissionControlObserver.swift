import Cocoa
import Combine

@MainActor
final class MissionControlObserver: ObservableObject {
    static let shared = MissionControlObserver()
    
    @Published private(set) var isMissionControlActive: Bool = false
    
    private var lastCheckTime: TimeInterval = 0
    private var cachedResult: Bool = false
    private var activeCheckTimer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []
    
    private init() {
        setupWorkspaceObservers()
    }
    
    /// Fast, non-blocking check whether macOS Mission Control / Exposé is currently active on screen.
    func checkIsMissionControlActive() -> Bool {
        let now = CACurrentMediaTime()
        // Cache result for 80ms to avoid hammering WindowServer on high-frequency mouse moves
        if now - lastCheckTime < 0.08 {
            return cachedResult
        }
        lastCheckTime = now
        
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            cachedResult = false
            if isMissionControlActive { isMissionControlActive = false }
            return false
        }
        
        for w in list {
            if (w[kCGWindowOwnerName as String] as? String) == "Dock" {
                let layer = w[kCGWindowLayer as String] as? Int ?? -1
                // Mission Control creates a nearly full-screen Dock canvas. Small
                // layer 18/20 Dock windows also exist during normal desktop use, so
                // a fixed 400pt threshold produces false positives and kills hover.
                if layer == 20 || layer == 18 {
                    let alpha = (w[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
                    guard alpha > 0.05 else { continue }
                    let boundsDict = w[kCGWindowBounds as String] as? NSDictionary
                    if let bounds = boundsDict.flatMap({ CGRect(dictionaryRepresentation: $0) }) {
                        let coversScreen = NSScreen.screens.contains { screen in
                            bounds.width >= screen.frame.width * 0.80 &&
                            bounds.height >= screen.frame.height * 0.80
                        }
                        if coversScreen {
                            cachedResult = true
                            if !isMissionControlActive { isMissionControlActive = true }
                            return true
                        }
                    }
                }
            }
        }
        
        cachedResult = false
        if isMissionControlActive { isMissionControlActive = false }
        return false
    }
    
    /// Start polling while the Notch is open to detect if the user invokes Mission Control via trackpad gesture or shortcut.
    func startMonitoring(onMissionControlDetected: @escaping () -> Void) {
        stopMonitoring()
        let timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if self.checkIsMissionControlActive() {
                    onMissionControlDetected()
                }
            }
        }
        timer.tolerance = 0.1
        activeCheckTimer = timer
    }
    
    func stopMonitoring() {
        activeCheckTimer?.invalidate()
        activeCheckTimer = nil
    }
    
    private func setupWorkspaceObservers() {
        let center = NSWorkspace.shared.notificationCenter
        
        // When active space changes (user clicked space/window in Mission Control),
        // invalidate cache immediately so hover is instantly re-enabled!
        let spaceToken = center.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.lastCheckTime = 0
                self?.cachedResult = false
                self?.isMissionControlActive = false
            }
        }
        workspaceObservers.append(spaceToken)
        
        // When user selects and activates an app, invalidate cache
        let appToken = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.lastCheckTime = 0
                self?.cachedResult = false
                self?.isMissionControlActive = false
            }
        }
        workspaceObservers.append(appToken)
    }
    
    deinit {
        activeCheckTimer?.invalidate()
        for token in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
    }
}
