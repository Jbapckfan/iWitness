import Foundation
import CryptoKit
import Security
#if os(iOS)
import UIKit
#endif

/// Handles encryption of video chunks using enveloped encryption
/// - Data Key: Random AES-256 key per incident
/// - Key Wrap: Data key encrypted with user's public key
/// - Forward Secrecy: Key derivation per chunk
class EncryptionService {
    // MARK: - Constants

    private let keyTag = "com.ontherecord.encryption.privatekey"
    private let publicKeyTag = "com.ontherecord.encryption.publickey"

    // MARK: - State

    private var incidentMasterKey: SymmetricKey?
    private var incidentSalt: Data?
    private var privateKey: SecKey?
    private var publicKey: SecKey?

    // Signing Keys (P256 for Elliptic Curve Signatures)
    // On devices with Secure Enclave (all iPhones since iPhone 5s), the signing key is
    // hardware-bound and non-extractable — the private key material never leaves the chip,
    // even on jailbroken devices. On simulator or older hardware, we fall back to a software key.
    private var secureEnclaveSigningKey: SecureEnclave.P256.Signing.PrivateKey?
    private var softwareSigningKey: P256.Signing.PrivateKey?

    // Thread safety
    private let lock = NSLock()

    // MARK: - Initialization

    init() {
        loadOrGenerateKeyPair()
    }

    // MARK: - Key Management

    /// Generates or loads the user's RSA key pair for key wrapping
    private func loadOrGenerateKeyPair() {
        // Try to load existing private key from Keychain
        if let existingKey = loadPrivateKey() {
            privateKey = existingKey
            publicKey = SecKeyCopyPublicKey(existingKey)
        } else {
            // Generate new key pair
            generateKeyPair()
        }

        // Bug fix: signing key must ALWAYS be loaded, not just when generating a new RSA pair.
        // Previously this was only called in the else branch, so the signing key was never
        // loaded when an existing RSA key was found in Keychain (i.e. every launch after first).
        loadOrGenerateSigningKey()
    }
    
    // MARK: - Signing Key Management (Admissibility)
    
    private let signingKeyTag = "com.ontherecord.signing.key"
    
    private func loadOrGenerateSigningKey() {
        if SecureEnclave.isAvailable {
            loadOrGenerateSecureEnclaveSigningKey()
        } else {
            // Fallback for simulator and devices without Secure Enclave
            loadOrGenerateSoftwareSigningKey()
        }
    }

    /// Loads or generates a Secure Enclave P256 signing key.
    /// The private key material NEVER leaves the Secure Enclave chip — it is non-extractable
    /// even with physical access or on jailbroken devices. The `dataRepresentation` stored in
    /// Keychain is an opaque handle that can only be used on the same device's SE hardware.
    private func loadOrGenerateSecureEnclaveSigningKey() {
        // Try to reload an existing Secure Enclave key from its persisted handle
        if let keyData = loadKeyData(tag: signingKeyTag),
           let key = try? SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: keyData) {
            self.secureEnclaveSigningKey = key
            debugLog("[EncryptionService] Loaded existing Secure Enclave signing key")
            return
        }

        // Generate a new Secure Enclave key
        do {
            let accessControl = SecAccessControlCreateWithFlags(
                nil,
                kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
                .privateKeyUsage,
                nil
            )
            // Note: We do NOT require biometric auth for signing — the key must be usable
            // during background recording without user interaction. The `.privateKeyUsage`
            // flag ensures the key can only be used for signing operations within the SE.

            let key: SecureEnclave.P256.Signing.PrivateKey
            if let ac = accessControl {
                key = try SecureEnclave.P256.Signing.PrivateKey(
                    accessControl: ac
                )
            } else {
                key = try SecureEnclave.P256.Signing.PrivateKey()
            }
            self.secureEnclaveSigningKey = key

            // Persist the opaque handle (NOT the private key — that never leaves the SE)
            saveKeyData(data: key.dataRepresentation, tag: signingKeyTag)
            debugLog("[EncryptionService] Generated new Secure Enclave signing key")
        } catch {
            debugLog("[EncryptionService] Secure Enclave key generation failed: \(error.localizedDescription). Falling back to software key.")
            // If SE key generation fails for any reason, fall back to software
            loadOrGenerateSoftwareSigningKey()
        }
    }

    /// Fallback: loads or generates a software P256 signing key (simulator, old hardware, SE failure).
    private func loadOrGenerateSoftwareSigningKey() {
        // Try to load existing software key from Keychain
        if let keyData = loadKeyData(tag: signingKeyTag),
           let key = try? P256.Signing.PrivateKey(rawRepresentation: keyData) {
            self.softwareSigningKey = key
            debugLog("[EncryptionService] Loaded existing software signing key")
            return
        }

        // Generate a new software P256 key
        let key = P256.Signing.PrivateKey()
        self.softwareSigningKey = key
        saveKeyData(data: key.rawRepresentation, tag: signingKeyTag)
        debugLog("[EncryptionService] Generated new software signing key (Secure Enclave not available)")
    }

    // MARK: - Signing Helpers

    /// The public key corresponding to whichever signing key is active (SE or software).
    /// Used for signature verification and export.
    var signingPublicKey: P256.Signing.PublicKey? {
        if let seKey = secureEnclaveSigningKey {
            return seKey.publicKey
        } else if let swKey = softwareSigningKey {
            return swKey.publicKey
        }
        return nil
    }

    /// Signs arbitrary data using the active signing key (Secure Enclave or software fallback).
    /// Both key types produce identical `P256.Signing.ECDSASignature` output.
    func sign(_ data: Data) throws -> P256.Signing.ECDSASignature {
        if let seKey = secureEnclaveSigningKey {
            return try seKey.signature(for: data)
        } else if let swKey = softwareSigningKey {
            return try swKey.signature(for: data)
        }
        throw EncryptionError.signingKeyUnavailable
    }
    
    private func saveKeyData(data: Data, tag: String) {
        // Delete any existing key first (upsert pattern)
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: tag
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: tag,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }
    
    private func loadKeyData(tag: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: tag,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var item: CFTypeRef?
        SecItemCopyMatching(query as CFDictionary, &item)
        return item as? Data
    }

    private func loadPrivateKey() -> SecKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keyTag,
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecReturnRef as String: true
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess, let cfItem = item else {
            return nil
        }
        // CFTypeRef from Keychain is always SecKey for kSecClassKey queries
        let key = cfItem as! SecKey
        return key
    }

    private func generateKeyPair() {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 4096,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: keyTag,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            ]
        ]

        var error: Unmanaged<CFError>?
        guard let privKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            debugLog("[OnTheRecord] Failed to generate key pair: \(error?.takeRetainedValue().localizedDescription ?? "unknown")")
            return
        }

        privateKey = privKey
        publicKey = SecKeyCopyPublicKey(privKey)
    }

    // MARK: - Incident Key Generation

    /// Generates a new master key and salt for an incident
    func generateIncidentKey() -> SymmetricKey {
        let key = SymmetricKey(size: .bits256)
        incidentMasterKey = key

        // Generate a random 32-byte salt for HKDF key derivation
        var saltBytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, saltBytes.count, &saltBytes)
        incidentSalt = Data(saltBytes)

        return key
    }

    /// Derives a chunk-specific key using HKDF with per-incident salt
    private func deriveChunkKey(masterKey: SymmetricKey, chunkNumber: Int, salt: Data) -> SymmetricKey {
        let info = "OnTheRecord-chunk-\(chunkNumber)".data(using: .utf8)!
        let derivedKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: masterKey,
            salt: salt,
            info: info,
            outputByteCount: 32
        )
        return derivedKey
    }

    // MARK: - Chunk Encryption

    /// Encrypts a video chunk with metadata
    func encryptChunk(_ data: Data, metadata: ChunkMetadata) throws -> EncryptedChunk {
        lock.lock()
        defer { lock.unlock() }

        if incidentMasterKey == nil {
            _ = generateIncidentKey()
        }
        guard let masterKey = incidentMasterKey,
              let salt = incidentSalt else {
            throw EncryptionError.encryptionFailed
        }

        // Derive chunk-specific key (forward secrecy) with per-incident salt
        let chunkKey = deriveChunkKey(masterKey: masterKey, chunkNumber: metadata.chunkNumber, salt: salt)

        // Serialize metadata (needed before encryption for AAD)
        let metadataJSON = try JSONEncoder().encode(metadata)

        // Generate random nonce
        let nonce = AES.GCM.Nonce()

        // Encrypt data with metadata as Associated Authenticated Data (AAD)
        // This cryptographically binds the metadata to the ciphertext, preventing metadata swapping
        let sealedBox = try AES.GCM.seal(data, using: chunkKey, nonce: nonce, authenticating: metadataJSON)

        // Compute HMAC of metadata
        let metadataHMAC = HMAC<SHA256>.authenticationCode(for: metadataJSON, using: chunkKey)

        // Wrap master key with user's public key (included in every chunk for resilience)
        let wrappedMasterKey = wrapKey(masterKey)

        // Compute hash of previous chunk for chain
        // (This would be passed in from the upload service in a real implementation)
        let previousHash = metadata.previousChunkHash

        // --- Admissibility Sealing (Digital Signature) ---
        // Uses Secure Enclave when available — signing happens inside the SE hardware,
        // the private key material never enters app memory.
        var signature: Data?
        do {
            var dataToSign = sealedBox.ciphertext
            dataToSign.append(sealedBox.tag)
            dataToSign.append(metadataJSON)
            if let prev = previousHash {
                dataToSign.append(prev)
            }

            let sig = try sign(dataToSign)
            signature = sig.rawRepresentation
        } catch {
            debugLog("[EncryptionService] Signing failed for chunk \(metadata.chunkNumber): \(error.localizedDescription)")
        }

        return EncryptedChunk(
            header: ChunkHeader(
                magic: "IWIT",
                version: 1,
                chunkNumber: metadata.chunkNumber,
                timestamp: metadata.timestamp,
                incidentID: metadata.incidentID
            ),
            encryptedPayload: sealedBox.ciphertext,
            nonce: Data(nonce),
            authTag: Data(sealedBox.tag),
            metadata: metadataJSON,
            metadataHMAC: Data(metadataHMAC),
            wrappedMasterKey: wrappedMasterKey,
            salt: salt,
            previousChunkHash: previousHash,
            signature: signature
        )
    }

    // MARK: - Chunk Decryption

    /// Decrypts a video chunk (for local playback)
    func decryptChunk(_ encryptedChunk: EncryptedChunk) throws -> Data {
        lock.lock()
        defer { lock.unlock() }

        // Unwrap master key from chunk if needed
        if incidentMasterKey == nil {
            if let wrappedKey = encryptedChunk.wrappedMasterKey,
               let unwrapped = unwrapKey(wrappedKey) {
                incidentMasterKey = unwrapped
            } else {
                throw EncryptionError.noMasterKey
            }
        }
        guard let masterKey = incidentMasterKey else {
            throw EncryptionError.noMasterKey
        }

        // Restore salt from chunk if needed
        if incidentSalt == nil {
            incidentSalt = encryptedChunk.salt
        }
        guard let salt = incidentSalt else {
            debugLog("[EncryptionService] No salt available for chunk \(encryptedChunk.header.chunkNumber)")
            throw EncryptionError.decryptionFailed
        }

        let chunkKey = deriveChunkKey(masterKey: masterKey, chunkNumber: encryptedChunk.header.chunkNumber, salt: salt)

        // Verify metadata HMAC before trusting metadata
        let expectedHMAC = HMAC<SHA256>.authenticationCode(for: encryptedChunk.metadata, using: chunkKey)
        guard Data(expectedHMAC) == encryptedChunk.metadataHMAC else {
            debugLog("[EncryptionService] HMAC verification failed for chunk \(encryptedChunk.header.chunkNumber)")
            throw EncryptionError.decryptionFailed
        }

        // Verify digital signature if present
        // Verification uses the public key only — works identically whether the signing key
        // lives in the Secure Enclave or is a software key.
        if let signatureData = encryptedChunk.signature, let pubKey = signingPublicKey {
            var dataToVerify = encryptedChunk.encryptedPayload
            dataToVerify.append(encryptedChunk.authTag)
            dataToVerify.append(encryptedChunk.metadata)
            if let prev = encryptedChunk.previousChunkHash {
                dataToVerify.append(prev)
            }
            guard let signature = try? P256.Signing.ECDSASignature(rawRepresentation: signatureData),
                  pubKey.isValidSignature(signature, for: dataToVerify) else {
                debugLog("[EncryptionService] Signature verification failed for chunk \(encryptedChunk.header.chunkNumber)")
                throw EncryptionError.decryptionFailed
            }
        }

        let nonce = try AES.GCM.Nonce(data: encryptedChunk.nonce)
        let sealedBox = try AES.GCM.SealedBox(
            nonce: nonce,
            ciphertext: encryptedChunk.encryptedPayload,
            tag: encryptedChunk.authTag
        )

        // Decrypt with metadata as AAD to verify cryptographic binding
        return try AES.GCM.open(sealedBox, using: chunkKey, authenticating: encryptedChunk.metadata)
    }

    // MARK: - Key Wrapping

    private func wrapKey(_ symmetricKey: SymmetricKey) -> Data? {
        guard let publicKey = publicKey else { return nil }

        let keyData = symmetricKey.withUnsafeBytes { Data($0) }

        var error: Unmanaged<CFError>?
        guard let encrypted = SecKeyCreateEncryptedData(
            publicKey,
            .rsaEncryptionOAEPSHA256,
            keyData as CFData,
            &error
        ) else {
            debugLog("[OnTheRecord] Key wrap failed: \(error?.takeRetainedValue().localizedDescription ?? "unknown")")
            return nil
        }

        return encrypted as Data
    }

    private func unwrapKey(_ wrappedKey: Data) -> SymmetricKey? {
        guard let privateKey = privateKey else { return nil }

        var error: Unmanaged<CFError>?
        guard let decrypted = SecKeyCreateDecryptedData(
            privateKey,
            .rsaEncryptionOAEPSHA256,
            wrappedKey as CFData,
            &error
        ) else {
            debugLog("[OnTheRecord] Key unwrap failed: \(error?.takeRetainedValue().localizedDescription ?? "unknown")")
            return nil
        }

        return SymmetricKey(data: decrypted as Data)
    }

    // MARK: - Public Key Export

    /// Exports public key for backup/recovery
    func exportPublicKey() -> Data? {
        guard let publicKey = publicKey else { return nil }

        var error: Unmanaged<CFError>?
        guard let data = SecKeyCopyExternalRepresentation(publicKey, &error) else {
            return nil
        }

        return data as Data
    }

    /// Exports the P256 signing public key for third-party verification.
    /// Works identically regardless of whether the key is in the Secure Enclave or software.
    func exportSigningPublicKey() -> Data? {
        return signingPublicKey?.rawRepresentation
    }

    // MARK: - Private Key Export/Import (Recovery)

    /// Exports the RSA private key and the signing PUBLIC key for recovery kit creation.
    ///
    /// **Secure Enclave trade-off:** The P256 signing private key is hardware-bound and
    /// non-extractable — it CANNOT be exported from the Secure Enclave, by design. This means:
    /// - The recovery kit includes the RSA private key (for decrypting footage) and the
    ///   signing PUBLIC key (for verifying signatures made by this device).
    /// - When restoring on a new device, a NEW signing key is generated in that device's
    ///   Secure Enclave. Old signatures remain verifiable using the exported public key.
    /// - This is the correct security trade-off: decryption capability transfers (RSA),
    ///   but signing identity is device-bound (P256/SE).
    func exportPrivateKeys() -> (rsaPrivateKey: Data, signingPublicKey: Data)? {
        guard let rsaKey = loadPrivateKey() else {
            debugLog("[EncryptionService] Failed to load RSA private key for export")
            return nil
        }

        var error: Unmanaged<CFError>?
        guard let rsaData = SecKeyCopyExternalRepresentation(rsaKey, &error) as Data? else {
            debugLog("[EncryptionService] Failed to export RSA private key: \(error?.takeRetainedValue().localizedDescription ?? "unknown")")
            return nil
        }

        // Export the signing PUBLIC key only — the private key never leaves the Secure Enclave
        guard let signingPubKeyData = signingPublicKey?.rawRepresentation else {
            debugLog("[EncryptionService] No signing key available for public key export")
            return nil
        }

        return (rsaData, signingPubKeyData)
    }

    /// Imports the RSA private key from recovery data and generates a NEW signing key.
    ///
    /// The `signingPublicKeyData` parameter is the public key from the old device, included
    /// for reference/logging only. A brand-new signing key is generated in this device's
    /// Secure Enclave (or software fallback) because Secure Enclave private keys are
    /// non-transferable by design. Signatures made by the old device remain verifiable
    /// using the old public key exported in the recovery kit.
    func importPrivateKeys(rsaPrivateKeyData: Data, signingPublicKeyData: Data) -> Bool {
        // --- 1. Import and validate RSA private key ---
        let rsaAttributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits as String: 4096
        ]

        var error: Unmanaged<CFError>?
        guard let rsaKey = SecKeyCreateWithData(rsaPrivateKeyData as CFData, rsaAttributes as CFDictionary, &error) else {
            debugLog("[EncryptionService] Failed to import RSA key: \(error?.takeRetainedValue().localizedDescription ?? "unknown")")
            return false
        }

        // --- 2. Delete existing RSA private key from Keychain ---
        let deletePrivateQuery: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keyTag,
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA
        ]
        SecItemDelete(deletePrivateQuery as CFDictionary)

        // --- 3. Save imported RSA private key to Keychain ---
        let savePrivateQuery: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keyTag,
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecValueRef as String: rsaKey,
            kSecAttrIsPermanent as String: true,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let saveStatus = SecItemAdd(savePrivateQuery as CFDictionary, nil)
        guard saveStatus == errSecSuccess else {
            debugLog("[EncryptionService] Failed to save imported RSA private key: \(saveStatus)")
            return false
        }

        // --- 4. Derive and update the RSA public key ---
        guard let rsaPublicKey = SecKeyCopyPublicKey(rsaKey) else {
            debugLog("[EncryptionService] Failed to derive public key from imported RSA key")
            return false
        }

        // --- 5. Generate a NEW signing key on this device ---
        // Secure Enclave keys are non-transferable: the old device's signing key cannot be
        // imported. We generate a fresh key in this device's Secure Enclave (or software
        // fallback). The old device's public key (signingPublicKeyData) can still be used
        // to verify signatures it produced — that verification happens via verifyChunkSignature().
        debugLog("[EncryptionService] Recovery: generating new signing key (old device's SE key is non-transferable)")
        if let oldPubKey = try? P256.Signing.PublicKey(rawRepresentation: signingPublicKeyData) {
            debugLog("[EncryptionService] Old device signing public key fingerprint preserved for verification: \(oldPubKey.rawRepresentation.prefix(8).map { String(format: "%02x", $0) }.joined())")
        }

        // Delete existing signing key data before generating new
        let deleteSigningQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: signingKeyTag
        ]
        SecItemDelete(deleteSigningQuery as CFDictionary)

        // Reset in-memory signing key state
        self.secureEnclaveSigningKey = nil
        self.softwareSigningKey = nil

        // Generate new signing key (SE or software fallback)
        loadOrGenerateSigningKey()

        // --- 6. Update in-memory RSA properties ---
        self.privateKey = rsaKey
        self.publicKey = rsaPublicKey

        debugLog("[EncryptionService] Successfully imported RSA key and generated new signing key")
        return true
    }

    /// Verifies a chunk's digital signature using a provided public key (third-party verification without decryption)
    func verifyChunkSignature(_ encryptedChunk: EncryptedChunk, publicKey: P256.Signing.PublicKey) -> Bool {
        guard let signatureData = encryptedChunk.signature else { return false }

        var dataToVerify = encryptedChunk.encryptedPayload
        dataToVerify.append(encryptedChunk.authTag)
        dataToVerify.append(encryptedChunk.metadata)
        if let prev = encryptedChunk.previousChunkHash {
            dataToVerify.append(prev)
        }

        guard let signature = try? P256.Signing.ECDSASignature(rawRepresentation: signatureData) else {
            return false
        }
        return publicKey.isValidSignature(signature, for: dataToVerify)
    }

    // MARK: - Key Revocation

    /// Revokes the master key and salt (footage remains encrypted but inaccessible)
    func revokeIncidentKey() {
        incidentMasterKey = nil
        incidentSalt = nil
    }

    // MARK: - Errors

    enum EncryptionError: LocalizedError {
        case noMasterKey
        case encryptionFailed
        case decryptionFailed
        case keyWrapFailed
        case signingKeyUnavailable

        var errorDescription: String? {
            switch self {
            case .noMasterKey:
                return "No master key available for encryption"
            case .encryptionFailed:
                return "Failed to encrypt chunk"
            case .decryptionFailed:
                return "Failed to decrypt chunk"
            case .keyWrapFailed:
                return "Failed to wrap/unwrap key"
            case .signingKeyUnavailable:
                return "No signing key available (Secure Enclave or software)"
            }
        }
    }
}

// MARK: - Supporting Types

struct ChunkMetadata: Codable {
    let incidentID: String
    let chunkNumber: Int
    let timestamp: Date
    let location: Location?
    let quality: String
    let deviceState: DeviceState
    var previousChunkHash: Data?

    init(incidentID: String, chunkNumber: Int, timestamp: Date, location: Location?, quality: AppState.VideoQuality, deviceState: DeviceState) {
        self.incidentID = incidentID
        self.chunkNumber = chunkNumber
        self.timestamp = timestamp
        self.location = location
        self.quality = quality.rawValue
        self.deviceState = deviceState
        self.previousChunkHash = nil
    }
}

struct DeviceState: Codable {
    let batteryLevel: Float
    let batteryState: String
    let networkType: String
    let orientation: String

    static func current() -> DeviceState {
        #if os(iOS)
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true

        let batteryState: String
        switch device.batteryState {
        case .charging: batteryState = "charging"
        case .full: batteryState = "full"
        case .unplugged: batteryState = "unplugged"
        case .unknown: batteryState = "unknown"
        @unknown default: batteryState = "unknown"
        }

        let orientation: String
        switch device.orientation {
        case .portrait: orientation = "portrait"
        case .landscapeLeft: orientation = "landscapeLeft"
        case .landscapeRight: orientation = "landscapeRight"
        case .portraitUpsideDown: orientation = "portraitUpsideDown"
        default: orientation = "unknown"
        }

        return DeviceState(
            batteryLevel: device.batteryLevel,
            batteryState: batteryState,
            networkType: "unknown", // Would need NWPathMonitor
            orientation: orientation
        )
        #else
        return DeviceState(
            batteryLevel: 1.0,
            batteryState: "unknown",
            networkType: "unknown",
            orientation: "unknown"
        )
        #endif
    }
}

struct ChunkHeader: Codable {
    let magic: String
    let version: Int
    let chunkNumber: Int
    let timestamp: Date
    let incidentID: String
}

struct EncryptedChunk: Codable {
    let header: ChunkHeader
    let encryptedPayload: Data
    let nonce: Data
    let authTag: Data
    let metadata: Data
    let metadataHMAC: Data
    let wrappedMasterKey: Data?
    let salt: Data // Per-incident HKDF salt for key derivation
    let previousChunkHash: Data?
    let signature: Data? // Digital Signature for Admissibility

    /// Serializes the chunk for transmission
    func serialize() -> Data {
        do {
            return try JSONEncoder().encode(self)
        } catch {
            debugLog("[EncryptionService] CRITICAL: Failed to serialize encrypted chunk: \(error.localizedDescription)")
            return Data()
        }
    }

    /// Computes SHA-256 hash of this chunk for chain
    func computeHash() -> Data {
        var hasher = SHA256()
        hasher.update(data: encryptedPayload)
        hasher.update(data: authTag)
        hasher.update(data: metadata)
        return Data(hasher.finalize())
    }
}
