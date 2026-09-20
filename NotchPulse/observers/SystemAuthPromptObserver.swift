//
//  SystemAuthPromptObserver.swift
//  NotchPulse
//
//  Created for NotchPulse - System Authorization & Touch ID Prompt Interception
//  Modernized to delegate to NotchPulseSystemAuthCoordinator for unified Face ID & Apple biometrics handling.
//

import AppKit
import Combine

@MainActor
final class SystemAuthPromptObserver: ObservableObject {
    static let shared = SystemAuthPromptObserver()
    
    private init() {
        NotchPulseSystemAuthCoordinator.shared.startObserving()
    }
    
    func cleanup() {
        NotchPulseSystemAuthCoordinator.shared.stopObserving()
    }
}
