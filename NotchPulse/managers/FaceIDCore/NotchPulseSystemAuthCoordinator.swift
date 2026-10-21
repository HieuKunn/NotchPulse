import Foundation

/// Inert coordinator: Face ID in NotchPulse is strictly limited to unlocking the lock screen.
/// Interception of system authorization dialogs, terminal quick auth, and password autofill
/// have been permanently disabled per project requirements.
@MainActor
final class NotchPulseSystemAuthCoordinator: NSObject {
    static let shared = NotchPulseSystemAuthCoordinator()

    override private init() {
        super.init()
    }

    func startObserving() {}
    func stopObserving() {}
    func updatePromptTimerState() {}
}
