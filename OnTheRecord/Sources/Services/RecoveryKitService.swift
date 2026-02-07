import Foundation
import CryptoKit
import Security
#if os(iOS)
import UIKit
#endif

/// A Recovery Kit contains encrypted private keys that can actually decrypt evidence.
/// Unlike the old KeyRecoveryService (which only exported public keys), this creates
/// an encrypted bundle of private keys that can be restored with a recovery code.
///
/// Usage:
///   1. User creates a Recovery Kit -> gets a RecoveryKit object + recovery code
///   2. User exports the RecoveryKit to a `.otr-recovery` file
///   3. User writes down the recovery code (XXXXX-XXXXX-XXXXX-XXXXX)
///   4. To restore: import the file + enter the recovery code -> keys are restored
///
/// Both the file AND code are needed. The file alone is useless without the code.
class RecoveryKitService {
    static let shared = RecoveryKitService()

    // MARK: - Types

    struct RecoveryKit: Codable {
        let encryptedPayload: Data       // AES-GCM encrypted private key material
        let nonce: Data                  // AES-GCM nonce
        let salt: Data                   // PBKDF2/HKDF salt for deriving key from recovery code
        let deviceName: String
        let exportDate: Date
        let version: Int                 // Format version for forward compatibility
    }

    // MARK: - Constants

    private let currentVersion = 1
    private let codeLength = 20 // 4 groups of 5 chars = XXXXX-XXXXX-XXXXX-XXXXX

    // Keychain tags (must match EncryptionService)
    private let rsaKeyTag = "com.ontherecord.encryption.privatekey"
    private let signingKeyTag = "com.ontherecord.signing.key"

    // MARK: - Public API

    /// Creates a Recovery Kit containing encrypted private keys plus a recovery code.
    /// Returns nil if keys haven't been generated yet.
    func createRecoveryKit() -> (kit: RecoveryKit, code: String)? {
        // 1. Gather private key material
        guard let keyMaterial = gatherPrivateKeyMaterial() else {
            debugLog("[RecoveryKit] Failed to gather private key material")
            return nil
        }

        // 2. Generate a random recovery code
        let code = generateRecoveryCode()

        // 3. Derive an encryption key from the code
        var saltBytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, saltBytes.count, &saltBytes) == errSecSuccess else {
            debugLog("[RecoveryKit] Failed to generate salt")
            return nil
        }
        let salt = Data(saltBytes)

        guard let derivedKey = deriveKey(from: code, salt: salt) else {
            debugLog("[RecoveryKit] Failed to derive key from recovery code")
            return nil
        }

        // 4. Encrypt the private key material with AES-GCM
        do {
            let nonce = AES.GCM.Nonce()
            let sealed = try AES.GCM.seal(keyMaterial, using: derivedKey, nonce: nonce)

            guard let combined = sealed.combined else {
                debugLog("[RecoveryKit] Failed to get combined sealed data")
                return nil
            }

            // combined = nonce + ciphertext + tag, but we store nonce separately for clarity
            let kit = RecoveryKit(
                encryptedPayload: combined,
                nonce: Data(nonce),
                salt: salt,
                deviceName: UIDevice.current.name,
                exportDate: Date(),
                version: currentVersion
            )

            debugLog("[RecoveryKit] Recovery kit created successfully")
            return (kit: kit, code: code)

        } catch {
            debugLog("[RecoveryKit] Encryption failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Exports a RecoveryKit to Data suitable for writing as an `.otr-recovery` file.
    func exportToFile(_ kit: RecoveryKit) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(kit)
            debugLog("[RecoveryKit] Exported recovery file (\(data.count) bytes)")
            return data
        } catch {
            debugLog("[RecoveryKit] Export failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Imports a RecoveryKit from `.otr-recovery` file data.
    func importFromFile(_ data: Data) -> RecoveryKit? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let kit = try decoder.decode(RecoveryKit.self, from: data)
            debugLog("[RecoveryKit] Imported recovery file (version \(kit.version), from \(kit.deviceName))")
            return kit
        } catch {
            debugLog("[RecoveryKit] Import failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Decrypts and restores keys from a Recovery Kit using the recovery code.
    /// Returns true if keys were successfully restored to the Keychain.
    func importRecoveryKit(_ kit: RecoveryKit, recoveryCode: String) -> Bool {
        // 1. Derive decryption key from code + salt
        guard let derivedKey = deriveKey(from: recoveryCode, salt: kit.salt) else {
            debugLog("[RecoveryKit] Failed to derive key during import")
            return false
        }

        // 2. Decrypt the payload
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: kit.encryptedPayload)
            let decryptedData = try AES.GCM.open(sealedBox, using: derivedKey)

            // 3. Parse and restore keys
            return restorePrivateKeys(from: decryptedData)

        } catch {
            debugLog("[RecoveryKit] Decryption failed (wrong code?): \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Private Helpers

    /// Gathers all private key material into a single Data blob for encryption.
    /// Format: [4-byte RSA length][RSA private key data][P256 signing key data]
    private func gatherPrivateKeyMaterial() -> Data? {
        // Export RSA private key
        guard let rsaPrivateKeyData = exportRSAPrivateKey() else {
            debugLog("[RecoveryKit] No RSA private key found")
            return nil
        }

        // Export P256 signing key
        guard let signingKeyData = loadKeychainData(tag: signingKeyTag) else {
            debugLog("[RecoveryKit] No signing key found")
            return nil
        }

        // Pack: [4-byte length of RSA key][RSA key bytes][signing key bytes]
        var material = Data()
        var rsaLength = UInt32(rsaPrivateKeyData.count)
        material.append(Data(bytes: &rsaLength, count: 4))
        material.append(rsaPrivateKeyData)
        material.append(signingKeyData)

        debugLog("[RecoveryKit] Gathered key material: RSA=\(rsaPrivateKeyData.count) bytes, Signing=\(signingKeyData.count) bytes")
        return material
    }

    /// Exports the RSA private key from the Keychain as external representation.
    private func exportRSAPrivateKey() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: rsaKeyTag,
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecReturnRef as String: true
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let item = item else {
            debugLog("[RecoveryKit] RSA key lookup failed: \(status)")
            return nil
        }
        // CFTypeRef from kSecClassKey + kSecReturnRef is guaranteed to be SecKey.
        // The compiler confirms the downcast always succeeds for CoreFoundation types.
        let key = item as! SecKey // swiftlint:disable:this force_cast

        var error: Unmanaged<CFError>?
        guard let data = SecKeyCopyExternalRepresentation(key, &error) else {
            debugLog("[RecoveryKit] RSA key export failed: \(error?.takeRetainedValue().localizedDescription ?? "unknown")")
            return nil
        }
        return data as Data
    }

    /// Loads raw key data from Keychain (used for P256 signing key stored as GenericPassword).
    private func loadKeychainData(tag: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: tag,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        return item as? Data
    }

    /// Restores private keys to the Keychain from decrypted material.
    private func restorePrivateKeys(from data: Data) -> Bool {
        guard data.count > 4 else {
            debugLog("[RecoveryKit] Decrypted data too short")
            return false
        }

        // Parse: [4-byte RSA length][RSA key bytes][signing key bytes]
        let rsaLength = data.withUnsafeBytes { $0.load(as: UInt32.self) }
        let rsaEnd = 4 + Int(rsaLength)

        guard rsaEnd <= data.count else {
            debugLog("[RecoveryKit] Invalid key material format")
            return false
        }

        let rsaKeyData = data[4..<rsaEnd]
        let signingKeyData = data[rsaEnd...]

        // Restore RSA private key
        let rsaSuccess = restoreRSAPrivateKey(Data(rsaKeyData))

        // Restore P256 signing key
        let signingSuccess = restoreSigningKey(Data(signingKeyData))

        if rsaSuccess && signingSuccess {
            debugLog("[RecoveryKit] All keys restored successfully")
            return true
        } else {
            debugLog("[RecoveryKit] Key restoration partial — RSA: \(rsaSuccess), Signing: \(signingSuccess)")
            return false
        }
    }

    /// Imports an RSA private key from external representation into the Keychain.
    private func restoreRSAPrivateKey(_ data: Data) -> Bool {
        // Delete existing key first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: rsaKeyTag,
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Import the key
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits as String: 4096
        ]

        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(data as CFData, attributes as CFDictionary, &error) else {
            debugLog("[RecoveryKit] RSA key import failed: \(error?.takeRetainedValue().localizedDescription ?? "unknown")")
            return false
        }

        // Store in Keychain
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: rsaKeyTag,
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecValueRef as String: key,
            kSecAttrIsPermanent as String: true,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status != errSecSuccess {
            debugLog("[RecoveryKit] RSA key Keychain store failed: \(status)")
            return false
        }
        return true
    }

    /// Restores the P256 signing key to the Keychain (stored as GenericPassword raw representation).
    private func restoreSigningKey(_ data: Data) -> Bool {
        // Validate it's a valid P256 key
        guard let _ = try? CryptoKit.P256.Signing.PrivateKey(rawRepresentation: data) else {
            debugLog("[RecoveryKit] Invalid P256 signing key data")
            return false
        }

        // Delete existing
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: signingKeyTag
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Store
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: signingKeyTag,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status != errSecSuccess {
            debugLog("[RecoveryKit] Signing key Keychain store failed: \(status)")
            return false
        }
        return true
    }

    /// Generates a random recovery code in XXXXX-XXXXX-XXXXX-XXXXX format.
    private func generateRecoveryCode() -> String {
        let chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789" // No 0/O/1/I to avoid confusion
        var code = ""
        for i in 0..<codeLength {
            if i > 0 && i % 5 == 0 {
                code += "-"
            }
            let index = Int.random(in: 0..<chars.count)
            code += String(chars[chars.index(chars.startIndex, offsetBy: index)])
        }
        return code
    }

    /// Derives a symmetric key from a recovery code using HKDF.
    /// HKDF is appropriate here because the recovery code has ~100 bits of entropy
    /// (20 chars from a 32-char alphabet). PBKDF2 work-factor stretching is unnecessary
    /// for high-entropy input and would only add latency without meaningful security benefit.
    private func deriveKey(from code: String, salt: Data) -> SymmetricKey? {
        // Normalize code: remove dashes, uppercase
        let normalizedCode = code.replacingOccurrences(of: "-", with: "").uppercased()
        guard let codeData = normalizedCode.data(using: .utf8),
              let infoData = "OnTheRecord-RecoveryKit-v1".data(using: .utf8) else { return nil }

        let key = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: codeData),
            salt: salt,
            info: infoData,
            outputByteCount: 32
        )
        return key
    }
}
