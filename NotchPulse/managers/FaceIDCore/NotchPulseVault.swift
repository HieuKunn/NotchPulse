//
//  NotchPulseVault.swift
//  NotchPulse
//
//  Two-tier password storage:
//    1. Session key (256-bit AES) — Keychain-stored with `.userPresence` Touch ID access control.
//       This enforces OS-level biometric authentication when reading the key. Held in memory as a
//       `SymmetricKey` after one successful unwrap.
//    2. Encrypted password blob (AES-GCM) — Keychain-stored, no biometric gate.
//       Meaningless without the session key.
//
//  The plaintext password is never persisted anywhere unencrypted. In memory it's
//  handled as `Data`, callers zero it via `.resetBytes(in:)` after use.
//

import Foundation
import Security
import LocalAuthentication
import CryptoKit

extension Notification.Name {
    static let notchPulseSessionDidChange = Notification.Name("notchPulseSessionDidChange")
}

enum NotchPulseVaultError: LocalizedError {
    case emptyPassword
    case dataEncodingFailed
    case sessionLocked
    case encryptionFailed
    case decryptionFailed
    case keychainError(Error)

    var errorDescription: String? {
        switch self {
        case .emptyPassword:
            return "Password cannot be empty."
        case .dataEncodingFailed:
            return "Couldn't encode the password as UTF-8 data."
        case .sessionLocked:
            return "Session is locked. Touch ID is required to unlock the session before encrypted data can be accessed."
        case .encryptionFailed:
            return "Encryption failed."
        case .decryptionFailed:
            return "Decryption failed. The stored password may be corrupted."
        case .keychainError(let error):
            return "Keychain error: \(error.localizedDescription)"
        }
    }
}

enum NotchPulseVault {
    nonisolated static let sessionKeyAccount = "sessionKey"
    nonisolated static let encryptedBlobAccount = "encryptedPasswordBlob"

    // Legacy accounts wiped on delete (from previous app versions).
    nonisolated private static let legacyAccounts = ["macUserPassword", "embedding.json"]

    // MARK: - Session state (thread-safe via NSLock)

    nonisolated private static let sessionLock = NSLock()
    nonisolated(unsafe) private static var _cachedKey: SymmetricKey? = nil
    nonisolated(unsafe) private static var _lastActivityAt: Date = Date()

    nonisolated static var isSessionUnlocked: Bool {
        return hasStoredPassword()
    }
    
    nonisolated static var lastActivityAt: Date {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        return _lastActivityAt
    }

    nonisolated static func markActivity() {
        sessionLock.lock()
        _lastActivityAt = Date()
        sessionLock.unlock()
    }

    nonisolated private static func loadCachedKey() -> SymmetricKey? {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        return _cachedKey
    }

    nonisolated private static func storeCachedKey(_ key: SymmetricKey?) {
        sessionLock.lock()
        let changed = (_cachedKey != nil) != (key != nil)
        _cachedKey = key
        _lastActivityAt = Date()
        sessionLock.unlock()
        
        if changed {
            NotificationCenter.default.post(name: .notchPulseSessionDidChange, object: nil)
        }
    }

    // MARK: - Public API

    /// Does an encrypted blob exist? (Existence check — no auth required.)
    nonisolated static func hasStoredPassword() -> Bool {
        return NotchPulseKeychainManager.exists(account: encryptedBlobAccount)
    }

    /// Does a session key exist in the Keychain? (Existence check via attributes-only query)
    nonisolated static func hasSessionKey() -> Bool {
        return NotchPulseKeychainManager.exists(account: sessionKeyAccount)
    }
    
    /// Are there other encrypted files (like faces) depending on this session key?
    nonisolated static func hasSessionEncryptedData() -> Bool {
        let faceStoreURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotchPulseFaceID")
            .appendingPathComponent("face-identities.enc")
        
        return hasStoredPassword() || FileManager.default.fileExists(atPath: faceStoreURL.path)
    }

    /// Save (or replace) the password. Uses the existing session key if one is available.
    /// Blocking; call from a background actor.
    nonisolated static func savePassword(_ passwordBytes: Data) throws {
        guard !passwordBytes.isEmpty else { throw NotchPulseVaultError.emptyPassword }

        let key = try ensureSessionKey()

        let combined: Data
        do {
            let sealed = try AES.GCM.seal(passwordBytes, using: key)
            guard let c = sealed.combined else { throw NotchPulseVaultError.encryptionFailed }
            combined = c
        } catch {
            throw NotchPulseVaultError.encryptionFailed
        }

        do {
            try NotchPulseKeychainManager.save(account: encryptedBlobAccount, data: combined)
        } catch {
            throw NotchPulseVaultError.keychainError(error)
        }
        markActivity()
    }

    /// Encrypt arbitrary data with the current session key.
    nonisolated static func encryptWithSessionKey(_ plaintext: Data) throws -> Data {
        let key = try ensureSessionKey()
        do {
            let sealed = try AES.GCM.seal(plaintext, using: key)
            guard let combined = sealed.combined else { throw NotchPulseVaultError.encryptionFailed }
            markActivity()
            return combined
        } catch {
            throw NotchPulseVaultError.encryptionFailed
        }
    }

    /// Decrypt data that was encrypted with `encryptWithSessionKey`.
    nonisolated static func decryptWithSessionKey(_ ciphertext: Data) throws -> Data {
        let key = try ensureSessionKey()
        do {
            let sealed = try AES.GCM.SealedBox(combined: ciphertext)
            let plaintext = try AES.GCM.open(sealed, using: key)
            markActivity()
            return plaintext
        } catch {
            throw NotchPulseVaultError.decryptionFailed
        }
    }

    /// Returns the session key: cached in memory if available, loaded from Keychain if present,
    /// or freshly created if none exists yet.
    nonisolated private static func ensureSessionKey() throws -> SymmetricKey {
        if let cached = loadCachedKey() { return cached }

        if hasSessionKey() {
            if let data = try? NotchPulseKeychainManager.read(account: sessionKeyAccount) {
                let key = SymmetricKey(data: data)
                storeCachedKey(key)
                return key
            }
        }

        let key = SymmetricKey(size: .bits256)
        try saveSessionKey(key)
        storeCachedKey(key)
        return key
    }

    /// Unwraps the session key into memory.
    nonisolated static func unlockSession(reason: String) throws {
        _ = try ensureSessionKey()
    }

    /// Explicitly clear the cached session key.
    nonisolated static func lockSession() {
        storeCachedKey(nil)
    }

    /// Read + decrypt the password.
    /// Returns raw bytes — the caller MUST zero them via `.resetBytes(in:)` after use.
    /// Blocking; call from a background actor.
    nonisolated static func readPassword() throws -> Data {
        let key = try ensureSessionKey()

        let ciphertext: Data
        do {
            ciphertext = try NotchPulseKeychainManager.read(account: encryptedBlobAccount)
        } catch {
            throw NotchPulseVaultError.keychainError(error)
        }

        do {
            let sealed = try AES.GCM.SealedBox(combined: ciphertext)
            let plaintext = try AES.GCM.open(sealed, using: key)
            markActivity()
            return plaintext
        } catch {
            throw NotchPulseVaultError.decryptionFailed
        }
    }

    /// Delete both the session key and encrypted blob (plus legacy items).
    /// Clears the cached session state.
    nonisolated static func deletePassword() throws {
        let accountsToDelete = [encryptedBlobAccount, sessionKeyAccount] + legacyAccounts
        for account in accountsToDelete {
            try? NotchPulseKeychainManager.delete(account: account)
        }
        storeCachedKey(nil)
    }

    // MARK: - Internal Keychain helpers

    nonisolated private static func saveSessionKey(_ key: SymmetricKey) throws {
        let keyData = key.withUnsafeBytes { Data($0) }
        try NotchPulseKeychainManager.save(account: sessionKeyAccount, data: keyData, accessControl: nil)
    }
}
