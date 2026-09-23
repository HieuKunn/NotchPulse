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
    nonisolated static func unlockSession(reason: String = "") async throws {
        _ = ensureSessionKey()
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
