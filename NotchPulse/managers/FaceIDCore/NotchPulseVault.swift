//
//  NotchPulseVault.swift
//  NotchPulse
//
//  Two-tier storage on NotchPulseKeychainManager: a Touch-ID-gated session key (unwrapped once per launch) wraps an ungated encrypted
//  password blob, safe to read anytime — including the lock screen, where no app UI exists to host a Touch ID prompt.
//  Touch ID authorizes the session; nothing yet authorizes each individual unlock beyond that (face recognition will).
//

import Foundation
import CryptoKit
import LocalAuthentication

enum NotchPulseVaultError: LocalizedError {
    case emptyPassword
    case sessionLocked
    case encryptionFailed
    case decryptionFailed
    case sessionKeyUnavailable

    var errorDescription: String? {
        switch self {
        case .emptyPassword:
            return "Password cannot be empty."
        case .sessionLocked:
            return "Session is locked. Authenticate with Touch ID before storing or using the password."
        case .encryptionFailed:
            return "Encryption failed."
        case .decryptionFailed:
            return "Decryption failed. The stored credential may be corrupted."
        case .sessionKeyUnavailable:
            return "The session key is missing, but encrypted data still exists that only it could read. Nothing has been deleted. Remove the stored password on the Password tab to clear both and start fresh."
        }
    }
}

extension Notification.Name {
    /// Fires whenever the cached session key changes, so anything encrypted under it (e.g. `NotchPulseFaceEnrollmentStore`) can reload
    /// itself instead of relying on each call site to remember to — a past bug had the sidebar's unlock forget this, leaving
    /// face unlock silently running on stale pre-unlock data.
    static let secureCredentialSessionDidChange = Notification.Name("NotchPulseVault.sessionDidChange")
}

enum NotchPulseVault {
    nonisolated private static let sessionKeyAccount = "sessionKey"
    nonisolated private static let passwordBlobAccount = "encryptedPassword"

    // MARK: - Session state (thread-safe via NSLock)

    nonisolated private static let sessionLock = NSLock()
    nonisolated(unsafe) private static var _cachedKey: SymmetricKey?
    /// Last unlock or successful `readPassword` — what `NotchPulseSessionAutoLocker` compares against the idle limit. Guarded by
    /// `sessionLock` alongside the key so the two can never be observed out of step.
    nonisolated(unsafe) private static var _lastActivityAt: Date?

    nonisolated private static func tryAutoLoadKey() -> SymmetricKey? {
        if NotchPulseKeychainManager.exists(account: sessionKeyAccount) {
            if let data = try? NotchPulseKeychainManager.read(account: sessionKeyAccount) {
                return SymmetricKey(data: data)
            }
        }
        return nil
    }

    @discardableResult
    nonisolated static func ensureSessionKey() -> SymmetricKey {
        sessionLock.lock()
        if let key = _cachedKey {
            sessionLock.unlock()
            return key
        }
        if let key = tryAutoLoadKey() {
            _cachedKey = key
            _lastActivityAt = Date()
            sessionLock.unlock()
            NotificationCenter.default.post(name: .secureCredentialSessionDidChange, object: nil)
            return key
        }
        // Generate new key and save to Keychain
        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        let access = NotchPulseKeychainManager.makeUserPresenceAccessControl()
        try? NotchPulseKeychainManager.save(
            account: sessionKeyAccount,
            data: keyData,
            accessControl: access
        )
        _cachedKey = key
        _lastActivityAt = Date()
        sessionLock.unlock()
        NotificationCenter.default.post(name: .secureCredentialSessionDidChange, object: nil)
        return key
    }

    nonisolated static var isSessionUnlocked: Bool {
        sessionLock.lock()
        if _cachedKey != nil {
            sessionLock.unlock()
            return true
        }
        if let key = tryAutoLoadKey() {
            _cachedKey = key
            _lastActivityAt = Date()
            sessionLock.unlock()
            return true
        }
        sessionLock.unlock()
        return !hasSessionEncryptedData
    }

    /// `nil` whenever the session is locked — there is no activity to age.
    nonisolated static var lastActivityAt: Date? {
        sessionLock.lock(); defer { sessionLock.unlock() }
        return _lastActivityAt
    }

    nonisolated private static func cachedKey() -> SymmetricKey? {
        sessionLock.lock()
        if let key = _cachedKey {
            sessionLock.unlock()
            return key
        }
        if let key = tryAutoLoadKey() {
            _cachedKey = key
            _lastActivityAt = Date()
            sessionLock.unlock()
            return key
        }
        sessionLock.unlock()
        return nil
    }

    nonisolated private static func setCachedKey(_ key: SymmetricKey?) {
        sessionLock.lock()
        let changed = (key != nil) != (_cachedKey != nil)
        _cachedKey = key
        _lastActivityAt = key == nil ? nil : Date()
        sessionLock.unlock()
        // Posted after releasing the lock — observers may call back into `isSessionUnlocked` (re-acquiring it) from a
        // background thread, so posting while still locked risks a real self-deadlock, not a theoretical one.
        guard changed else { return }
        NotificationCenter.default.post(name: .secureCredentialSessionDidChange, object: nil)
    }

    /// Resets the idle countdown on each successful use, so an actively-used session never auto-locks.
    nonisolated private static func recordActivity() {
        sessionLock.lock()
        if _cachedKey != nil { _lastActivityAt = Date() }
        sessionLock.unlock()
    }

    // MARK: - Generic session-key crypto (shared by passwords here and face embeddings in NotchPulseSecureFaceStore; requires an unlocked session)

    nonisolated static func encrypt(_ plaintext: Data) throws -> Data {
        let key = ensureSessionKey()
        do {
            let sealed = try AES.GCM.seal(plaintext, using: key)
            guard let combined = sealed.combined else { throw NotchPulseVaultError.encryptionFailed }
            return combined
        } catch {
            throw NotchPulseVaultError.encryptionFailed
        }
    }

    nonisolated static func decrypt(_ ciphertext: Data) throws -> Data {
        let key = ensureSessionKey()
        do {
            let sealed = try AES.GCM.SealedBox(combined: ciphertext)
            return try AES.GCM.open(sealed, using: key)
        } catch {
            throw NotchPulseVaultError.decryptionFailed
        }
    }

    // MARK: - Public API

    nonisolated static func hasStoredPassword() -> Bool {
        NotchPulseKeychainManager.exists(account: passwordBlobAccount)
    }

    nonisolated static func hasSessionKey() -> Bool {
        NotchPulseKeychainManager.exists(account: sessionKeyAccount)
    }

    /// Ensures the session key is unlocked and ready for use.
    ///
    /// If the key is already cached in memory, returns immediately. Otherwise it creates
    /// an `LAContext`, evaluates `.deviceOwnerAuthentication` (Touch ID → Apple Watch →
    /// device password — whichever the user has available), then reads the session key
    /// from the Keychain using that authorised context. This is the only path that can
    /// surface a Touch ID / password prompt; every other entry point that reads the key
    /// either hits the in-memory cache or silently fails without an LAContext.
    nonisolated static func unlockSession(reason: String = "") async throws {
        // Fast path — key already in memory, nothing to do.
        sessionLock.lock()
        if _cachedKey != nil {
            sessionLock.unlock()
            return
        }
        sessionLock.unlock()

        let displayReason = reason.isEmpty
            ? "Authenticate to enable Face Unlock"
            : reason

        // Evaluate the policy first so the LAContext holds a reusable credential that
        // the subsequent Keychain read can consume without a second prompt.
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"

        var policyError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError) else {
            throw policyError ?? KeychainError.authenticationFailed
        }

        // This is the call that surfaces the Touch ID sheet / password dialog.
        _ = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: displayReason)

        // Read the Keychain item using the now-authorised context so the OS doesn't
        // prompt a second time. If no key exists yet (first-time setup), generate one
        // and save it — the LAContext keeps the session authorised for the save too.
        let key: SymmetricKey
        do {
            let keyData = try NotchPulseKeychainManager.read(account: sessionKeyAccount, context: context)
            key = SymmetricKey(data: keyData)
        } catch KeychainError.itemNotFound {
            // First-time setup: generate a new session key and persist it.
            let newKey = SymmetricKey(size: .bits256)
            let keyData = newKey.withUnsafeBytes { Data($0) }
            let access = NotchPulseKeychainManager.makeUserPresenceAccessControl()
            try NotchPulseKeychainManager.save(account: sessionKeyAccount, data: keyData, accessControl: access)
            key = newKey
        }
        setCachedKey(key)
    }

    /// Checked without needing the key itself, so this stays answerable precisely when the key can't be read.
    nonisolated static var hasSessionEncryptedData: Bool {
        NotchPulseKeychainManager.exists(account: passwordBlobAccount) || NotchPulseSecureFaceStore.exists
    }

    /// Clears the cached session key. Next save/read requires Touch ID again.
    nonisolated static func lockSession() {
        setCachedKey(nil)
    }

    /// Encrypts and stores `passwordBytes`. Requires an unlocked session —
    /// call `unlockSession(reason:)` first. Blocking; call from a background task.
    nonisolated static func savePassword(_ passwordBytes: Data) throws {
        guard !passwordBytes.isEmpty else { throw NotchPulseVaultError.emptyPassword }
        let combined = try encrypt(passwordBytes)
        try NotchPulseKeychainManager.save(account: passwordBlobAccount, data: combined)
    }

    /// No separate Touch ID prompt — only the session key was gated, at unlock time. Caller MUST zero the returned bytes via
    /// `.resetBytes(in:)` after use. Blocking; call from a background task.
    nonisolated static func readPassword() throws -> Data {
        guard cachedKey() != nil else { throw NotchPulseVaultError.sessionLocked }
        let ciphertext = try NotchPulseKeychainManager.read(account: passwordBlobAccount)
        let plaintext = try decrypt(ciphertext)
        // Only on success: a failed read shouldn't extend the idle window.
        recordActivity()
        return plaintext
    }

    /// Deletes both Keychain items and clears the cached session key.
    nonisolated static func deletePassword() throws {
        try NotchPulseKeychainManager.delete(account: passwordBlobAccount)
        try NotchPulseKeychainManager.delete(account: sessionKeyAccount)
        setCachedKey(nil)
    }
}
