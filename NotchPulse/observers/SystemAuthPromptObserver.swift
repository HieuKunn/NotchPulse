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
