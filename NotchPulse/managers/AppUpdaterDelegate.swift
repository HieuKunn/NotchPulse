import Foundation
import Sparkle
import Combine

class AppUpdaterDelegate: NSObject, SPUUpdaterDelegate, ObservableObject {
    static let shared = AppUpdaterDelegate()
    
    @Published var isUpdateAvailable = false
    @Published var latestVersionString = ""
    
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        DispatchQueue.main.async {
            self.isUpdateAvailable = true
            self.latestVersionString = item.displayVersionString
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
}
