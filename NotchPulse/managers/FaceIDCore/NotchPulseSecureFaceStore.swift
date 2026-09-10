//
//  NotchPulseSecureFaceStore.swift
//  NotchPulse
//
//  Serializes, encrypts via NotchPulseVault, and persists enrolled faces to disk.
//  Meaningless without the Touch-ID-gated session key from the Keychain.
//  Ported from Glance's SecureFaceStore.swift with NotchPulse naming.
//

import Foundation

enum NotchPulseSecureFaceStore {
    private static let fileName = "face-identities.enc"

    /// The App Support directory.
    private static var storageDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let bundleID = Bundle.main.bundleIdentifier ?? "com.notchpulse.app"
        return appSupport.appendingPathComponent(bundleID)
    }

    private static var fileURL: URL {
        storageDirectory.appendingPathComponent(fileName)
    }

    /// Exists even if the session is locked. Used to detect whether the user has set anything up yet.
    static var exists: Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }

    /// Reads, decrypts, and decodes. Throws if the file is missing, unreadable, or fails decryption.
    static func load() throws -> [FaceIdentity] {
        guard exists else { return [] }

        let ciphertext = try Data(contentsOf: fileURL)
        let plaintext = try NotchPulseVault.decryptWithSessionKey(ciphertext)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([FaceIdentity].self, from: plaintext)
    }

    /// Encodes, encrypts, and writes to disk atomically.
    static func save(_ identities: [FaceIdentity]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        let plaintext = try encoder.encode(identities)
        let ciphertext = try NotchPulseVault.encryptWithSessionKey(plaintext)

        try FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true, attributes: nil)
        try ciphertext.write(to: fileURL, options: .atomic)
    }

    /// Unconditionally removes the file. Used during a full teardown.
    static func deleteAll() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
