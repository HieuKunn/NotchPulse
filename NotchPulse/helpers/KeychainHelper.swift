//
//  KeychainHelper.swift
//  NotchPulse
//
//  Created for NotchPulse v2.0 - Face ID Unlock Security
//

import Foundation
import Security

final class KeychainHelper {
    static let shared = KeychainHelper()
    
    private let service = "com.notchpulse.faceid"
    private let account = "user_unlock_credential"
    
    private init() {}
    
    /// Saves or updates the login password securely in the macOS Keychain
    @discardableResult
    func savePassword(_ password: String) -> Bool {
        guard let data = password.data(using: .utf8) else { return false }
        
        // Delete existing item first to avoid duplicate errors
        deletePassword()
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    /// Retrieves the stored login password from macOS Keychain
    func readPassword() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        guard status == errSecSuccess, let data = dataTypeRef as? Data else {
            return nil
        }
        
        return String(data: data, encoding: .utf8)
    }
    
    /// Checks whether a password has already been enrolled in the Keychain
    var hasPassword: Bool {
        readPassword() != nil
    }
    
    /// Deletes the stored password from Keychain
    @discardableResult
    func deletePassword() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
