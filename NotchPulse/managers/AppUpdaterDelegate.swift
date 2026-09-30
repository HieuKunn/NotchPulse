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

    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        DispatchQueue.main.async {
            AppDelegate.shared?.isUserInitiatedQuit = true
            AppDelegate.shared?.cleanupForTermination()
        }
    }
}
