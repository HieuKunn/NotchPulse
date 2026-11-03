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
        if Thread.isMainThread {
            AppDelegate.shared?.isUserInitiatedQuit = true
            AppDelegate.shared?.cleanupForTermination()
        } else {
            DispatchQueue.main.sync {
                AppDelegate.shared?.isUserInitiatedQuit = true
                AppDelegate.shared?.cleanupForTermination()
            }
        }
    }

    // MARK: - SPUStandardUserDriverDelegate
    
    /// Returns false so Sparkle delegates presenting the scheduled update to us.
    /// In an accessory (LSUIElement) app, Sparkle's default scheduler defers showing the update alert
    /// until NSApplicationDidBecomeActiveNotification, which never fires for menu-bar apps.
    /// By returning false, we intercept it and immediately invoke checkForUpdates() with .regular policy.
    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        return false
    }

    /// Called before an update dialog is presented.
    /// In an accessory (LSUIElement) app, elevating to .regular activation policy ensures
    /// the update prompt window pops up in the foreground instead of being hidden behind other apps.
    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            AppDelegate.shared?.collapseAllNotches(force: true)
            
            if !handleShowingUpdate {
                SettingsWindowController.shared.updaterController?.updater.checkForUpdates()
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                NSApp.activate(ignoringOtherApps: true)
                for window in NSApp.windows where window.className.contains("SU") || window.title.contains("Update") {
                    window.makeKeyAndOrderFront(nil)
                    window.orderFrontRegardless()
                }
            }
        }
    }

    /// Called before showing a modal alert window (e.g. "You're up to date!").
    /// In an accessory (LSUIElement) app, showing a modal alert without switching to .regular
    /// activation policy and raising window level causes the alert to be trapped behind
    /// high-level overlay windows, deadlocking the main thread runloop.
    func standardUserDriverWillShowModalAlert() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        AppDelegate.shared?.collapseAllNotches(force: true)
    }

    /// Called after showing a modal alert window. Restores accessory mode if Settings is not visible.
    func standardUserDriverDidShowModalAlert() {
        DispatchQueue.main.async {
            if SettingsWindowController.shared.window?.isVisible != true {
                NSApp.setActivationPolicy(.accessory)
            }
            AppDelegate.shared?.adjustWindowPosition(changeAlpha: false)
        }
    }

    /// Called when the update session finishes (e.g. dismissed, skipped, or finished).
    func standardUserDriverWillFinishUpdateSession() {
        DispatchQueue.main.async {
            if SettingsWindowController.shared.window?.isVisible != true {
                NSApp.setActivationPolicy(.accessory)
            }
            AppDelegate.shared?.adjustWindowPosition(changeAlpha: false)
        }
    }
}

