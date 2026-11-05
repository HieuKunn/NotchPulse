import Foundation
import Observation

@Observable
@MainActor
final class NotchPulsePOCController {
    static let shared = NotchPulsePOCController()

    private let monitor = NotchPulseLockMonitor()

    var accessibilityGranted: Bool = KeystrokeInjector.isAccessibilityTrusted()

    var hasStoredPassword: Bool = NotchPulseVault.hasStoredPassword()
    var isSessionUnlocked: Bool = NotchPulseVault.isSessionUnlocked
    var sessionError: String? = nil

    /// Bound to the setup SecureField. Cleared immediately after a successful save.
    var passwordInput: String = ""

    var statusMessage: String = "Idle"

    func refreshAccessibilityStatus() {
        accessibilityGranted = KeystrokeInjector.isAccessibilityTrusted()
    }

    func requestAccessibility() {
        KeystrokeInjector.promptForAccessibility()
    }

    func refreshCredentialStatus() {
        hasStoredPassword = NotchPulseVault.hasStoredPassword()
        isSessionUnlocked = NotchPulseVault.isSessionUnlocked
    }

    // MARK: - Session (Touch ID gate)

    /// Must succeed before `savePassword()` or `injectStoredPassword()` will do anything.
    func unlockSession() async {
        sessionError = nil
        do {
            try await NotchPulseVault.unlockSession(reason: "Authenticate to set up or use NotchPulse")
            isSessionUnlocked = true
        } catch {
            isSessionUnlocked = false
            sessionError = error.localizedDescription
        }
    }

    func lockSession() {
        NotchPulseVault.lockSession()
        isSessionUnlocked = false
    }

    // MARK: - Setup flow

    /// Encrypts and stores `passwordInput`. Requires the session to already
    /// be unlocked (Touch ID happens in `unlockSession()`, not here).
    func savePassword() async {
        guard !passwordInput.isEmpty else {
            statusMessage = "Enter a password first."
            return
        }
        let plaintext = passwordInput
        passwordInput = ""

        do {
            try await Task.detached(priority: .userInitiated) {
                guard var bytes = plaintext.data(using: .utf8) else {
                    throw NotchPulseVaultError.emptyPassword
                }
                defer { bytes.resetBytes(in: 0..<bytes.count) }
                try NotchPulseVault.savePassword(bytes)
            }.value
            statusMessage = "Password saved and encrypted."
            hasStoredPassword = true
        } catch {
            statusMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Injection

    /// Reads + decrypts + injects the stored password, zeroing the plaintext
    /// buffer before returning. When `requireAuthoritativeLock` is true (the
    /// auto-trigger path), refuses to inject unless the CGSession dictionary
    /// confirms the screen is actually locked.
    func injectStoredPassword(requireAuthoritativeLock: Bool = false) async {
        let isTrusted = KeystrokeInjector.isAccessibilityTrusted()
        let isSessionUnlocked = NotchPulseVault.isSessionUnlocked
        NSLog("[FaceID-Inject] injectStoredPassword called: isAccessibilityTrusted=\(isTrusted), isSessionUnlocked=\(isSessionUnlocked), requireAuthoritativeLock=\(requireAuthoritativeLock)")

        guard isTrusted else {
            statusMessage = "Accessibility not granted — open System Settings and enable NotchPulse."
            NSLog("[FaceID-Inject] FAILED: Accessibility permission missing (AXIsProcessTrusted == false). Please toggle NotchPulse in System Settings -> Privacy & Security -> Accessibility.")
            return
        }
        guard isSessionUnlocked else {
            statusMessage = "Session locked — authenticate with Touch ID first."
            NSLog("[FaceID-Inject] FAILED: NotchPulseVault session locked. Stored password not loaded in memory.")
            return
        }

        if requireAuthoritativeLock {
            let actuallyLocked = NotchPulseLockMonitor.isScreenActuallyLocked()
            NSLog("[FaceID-Inject] Checking isScreenActuallyLocked: \(actuallyLocked)")
            guard actuallyLocked else {
                statusMessage = "Skipped: CGSession reports screen is not actually locked."
                NSLog("[FaceID-Inject] SKIPPED: CGSession reports screen is not actually locked.")
                return
            }
        }

        statusMessage = "Injecting…"
        do {
            try await Task.detached(priority: .userInitiated) {
                var bytes = try NotchPulseVault.readPassword()
                defer { bytes.resetBytes(in: 0..<bytes.count) }
                NSLog("[FaceID-Inject] readPassword retrieved \(bytes.count) bytes. Injecting keystrokes...")
                try KeystrokeInjector.typeAndReturn(bytes)
            }.value
            statusMessage = "Injected stored password + Return at \(Date().formatted(date: .omitted, time: .standard))"
            NSLog("[FaceID-Inject] SUCCESS: Injected stored password and pressed Return.")
        } catch {
            statusMessage = "Injection failed: \(error.localizedDescription)"
            NSLog("[FaceID-Inject] FAILED with error: \(error)")
        }
    }
}
