import Foundation
import Security

/// Secure credential storage using iOS Keychain
/// Used for storing sensitive data like API tokens that should not be in UserDefaults
final class KeychainService {
    
    // MARK: - Singleton
    
    static let shared = KeychainService()
    private init() {}
    
    // MARK: - Keys
    
    enum Key: String {
        case twilioAccountSID = "com.ontherecord.twilio.accountSID"
        case twilioAuthToken = "com.ontherecord.twilio.authToken"
        case twilioFromNumber = "com.ontherecord.twilio.fromNumber"
        case encryptionMasterKey = "com.ontherecord.encryption.masterKey"
    }
    
    // MARK: - Errors
    
    enum KeychainError: Error, LocalizedError {
        case itemNotFound
        case duplicateItem
        case unexpectedStatus(OSStatus)
        case encodingError
        
        var errorDescription: String? {
            switch self {
            case .itemNotFound:
                return "Item not found in Keychain"
            case .duplicateItem:
                return "Item already exists in Keychain"
            case .unexpectedStatus(let status):
                return "Keychain error: \(status)"
            case .encodingError:
                return "Failed to encode data for Keychain"
            }
        }
    }
    
    // MARK: - Public API
    
    /// Save a string value to Keychain
    func save(_ value: String, for key: Key) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingError
        }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        
        // Delete existing item first
        SecItemDelete(query as CFDictionary)
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
    
    /// Retrieve a string value from Keychain
    func get(_ key: Key) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw KeychainError.itemNotFound
            }
            throw KeychainError.unexpectedStatus(status)
        }
        
        guard let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.encodingError
        }
        
        return string
    }
    
    /// Delete a value from Keychain
    func delete(_ key: Key) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
    
    /// Check if a key exists in Keychain
    func exists(_ key: Key) -> Bool {
        do {
            _ = try get(key)
            return true
        } catch {
            return false
        }
    }
    
    // MARK: - Convenience Methods for Twilio
    
    /// Store complete Twilio configuration securely
    func saveTwilioConfig(accountSID: String, authToken: String, fromNumber: String) throws {
        try save(accountSID, for: .twilioAccountSID)
        try save(authToken, for: .twilioAuthToken)
        try save(fromNumber, for: .twilioFromNumber)
    }
    
    /// Retrieve Twilio configuration
    func getTwilioConfig() -> (accountSID: String, authToken: String, fromNumber: String)? {
        guard let accountSID = try? get(.twilioAccountSID),
              let authToken = try? get(.twilioAuthToken),
              let fromNumber = try? get(.twilioFromNumber) else {
            return nil
        }
        return (accountSID, authToken, fromNumber)
    }
    
    /// Clear all Twilio credentials
    func clearTwilioConfig() {
        try? delete(.twilioAccountSID)
        try? delete(.twilioAuthToken)
        try? delete(.twilioFromNumber)
    }
}
