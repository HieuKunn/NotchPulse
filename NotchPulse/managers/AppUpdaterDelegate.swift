import Foundation
import Sparkle
import Combine
import AppKit

class AppUpdaterDelegate: NSObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate, ObservableObject {
    static let shared = AppUpdaterDelegate()
    
    @Published var isUpdateAvailable = false
    @Published var latestVersionString = ""
    
    // MARK: - SPUUpdaterDelegate
    
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        DispatchQueue.main.async {
            self.isUpdateAvailable = true
            self.latestVersionString = item.displayVersionString
        }
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        DispatchQueue.main.async {
            self.isUpdateAvailable = false
        }
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        DispatchQueue.main.async {
            if let error = error as NSError?, error.domain == "SUSparkleErrorDomain" && error.code == 1001 {
                self.isUpdateAvailable = false
            }
        }
    }

    // CRITICAL: DO NOT DELETE!
    // Sparkle calls this delegate method right before it terminates the running application to install
    // the new update and relaunch. If windows and helpers are not cleaned up properly here, macOS may
    // prevent termination or Sparkle's Autoupdate helper may fail to replace the running app bundle in /Applications.
    // This causes an infinite update loop where the app restarts into the old version and repeatedly asks to update.
    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        DispatchQueue.main.async {
            AppDelegate.shared?.isUserInitiatedQuit = true
            AppDelegate.shared?.cleanupForTermination()
        }
    }

    // MARK: - SPUStandardUserDriverDelegate
    
    /// Called before showing a modal alert window (e.g. "You're up to date!").
    /// In an accessory (LSUIElement) app, showing a modal alert without switching to .regular
    /// activation policy and raising window level causes the alert to be trapped behind
    /// high-level overlay windows, deadlocking the main thread runloop.
    func standardUserDriverWillShowModalAlert() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.async {
            for window in NSApp.windows {
                let className = String(describing: type(of: window))
                // Only elevate and center actual Sparkle modal dialogs / system alerts.
                // NEVER touch, re-level, or center Notch windows or background panels!
                guard !(window is NotchPulseSkyLightWindow),
                      !(window is NotchPulseWindow),
                      !(window is LockScreenMediaWindow),
                      className != "NSStatusBarWindow" else {
                    continue
                }

                if className.contains("Alert") || className.contains("SU") || window.level == .modalPanel {
                    window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 10)
                    window.center()
                    window.orderFrontRegardless()
                    window.makeKeyAndOrderFront(nil)
                }
            }
        }
    }

    /// Called after showing a modal alert window. Restores accessory mode if Settings is not visible.
    func standardUserDriverDidShowModalAlert() {
        DispatchQueue.main.async {
            if SettingsWindowController.shared.window?.isVisible != true {
                NSApp.setActivationPolicy(.accessory)
            }
            AppDelegate.shared?.updateNotchPulseWindowPosition(changeAlpha: false)
        }
    }
}

