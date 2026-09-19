//
//  NotchPulseSecureFaceStore.swift
//  NotchPulse
//
//  Low-level encrypted persistence for enrolled face identities — AES-GCM under the same session key NotchPulseVault
//  uses for the Mac password, rather than a second key. `NotchPulseFaceEnrollmentStore` delegates its load/save here; no plaintext fallback.
//

import Foundation

enum NotchPulseSecureFaceStoreError: LocalizedError {
    case sessionLocked

    var errorDescription: String? {
        switch self {
        case .sessionLocked:
            return "Session is locked. Authenticate with Touch ID to access enrolled faces."
        }
    }
}

nonisolated enum NotchPulseSecureFaceStore {
    /// Distinct filename/extension so plaintext can never be mistaken for ciphertext.
    private static let fileURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = appSupport.appendingPathComponent("NotchPulse", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("face-identities.enc")
    }()

    /// True if a store exists on disk, regardless of whether the session is currently unlocked enough to read it.
    static var exists: Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }

    /// Throws `.sessionLocked` rather than returning an empty array, so callers can distinguish "nothing enrolled" from "enrolled, but locked".
    static func load() throws -> [FaceIdentity] {
        guard NotchPulseVault.isSessionUnlocked else { throw NotchPulseSecureFaceStoreError.sessionLocked }
        guard let ciphertext = try? Data(contentsOf: fileURL) else { return [] }
        let plaintext = try NotchPulseVault.decrypt(ciphertext)
        return try JSONDecoder().decode([FaceIdentity].self, from: plaintext)
    }

    static func save(_ identities: [FaceIdentity]) throws {
        guard NotchPulseVault.isSessionUnlocked else { throw NotchPulseSecureFaceStoreError.sessionLocked }
        let plaintext = try JSONEncoder().encode(identities)
        let ciphertext = try NotchPulseVault.encrypt(plaintext)
        try ciphertext.write(to: fileURL, options: .atomic)
    }

    static func deleteAll() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
