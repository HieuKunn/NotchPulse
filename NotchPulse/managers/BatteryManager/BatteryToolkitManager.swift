import Foundation
import SwiftUI
import Combine

@MainActor
final class BatteryToolkitManager: ObservableObject {
    static let shared = BatteryToolkitManager()
    
    @Published var minCharge: Int = 20
    @Published var maxCharge: Int = 100
    @Published var adapterSleep: Bool = false
    @Published var magSafeSync: Bool = false
    
    @Published var isSupported: Bool = true
    @Published var isLoading: Bool = true
    
    init() {
        Task {
            await loadSettings()
        }
    }
    
    func loadSettings() async {
        do {
            let settings = try await BTActions.getSettings()
            
            if let min = settings[BTSettingsInfo.Keys.minCharge] as? NSNumber {
                self.minCharge = min.intValue
            }
            if let max = settings[BTSettingsInfo.Keys.maxCharge] as? NSNumber {
                self.maxCharge = max.intValue
            }
            if let sleep = settings[BTSettingsInfo.Keys.adapterSleep] as? NSNumber {
                self.adapterSleep = !sleep.boolValue // UI shows "disable sleep", so we invert adapterSleep
            }
            if let sync = settings[BTSettingsInfo.Keys.magSafeSync] as? NSNumber {
                self.magSafeSync = sync.boolValue
            }
            
            self.isLoading = false
            self.isSupported = true
        } catch {
            self.isLoading = false
            self.isSupported = false
        }
    }
    
    func saveSettings() {
        let settings: [String: NSObject & Sendable] = [
            BTSettingsInfo.Keys.minCharge: NSNumber(value: minCharge),
            BTSettingsInfo.Keys.maxCharge: NSNumber(value: maxCharge),
            BTSettingsInfo.Keys.adapterSleep: NSNumber(value: !adapterSleep),
            BTSettingsInfo.Keys.magSafeSync: NSNumber(value: magSafeSync),
        ]
        
        Task {
            do {
                try await BTDaemonXPCClient.setSettings(settings: settings)
            } catch {
                print("Failed to save settings: \(error)")
            }
        }
    }
    
    func requestFullCharge() {
        BTDaemonXPCClient.chargeToFull()
    }
    
    func requestMaxCharge() {
        BTDaemonXPCClient.chargeToMaximum()
    }
    
    func disableCharging() {
        BTDaemonXPCClient.disableCharging()
    }
    
    func disablePowerAdapter() {
        BTDaemonXPCClient.disablePowerAdapter()
    }
    
    func enablePowerAdapter() {
        BTDaemonXPCClient.enablePowerAdapter()
    }
}
