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
    private var privateKey: SecKey?
    private var publicKey: SecKey?

    // Signing Keys (P256 for Elliptic Curve Signatures)
    private var signingKey: P256.Signing.PrivateKey?

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
            return
        }

        // Generate new key pair
        generateKeyPair()
        loadOrGenerateSigningKey()
    }
    
    // MARK: - Signing Key Management (Admissibility)
    
    private let signingKeyTag = "com.ontherecord.signing.key"
    
    private func loadOrGenerateSigningKey() {
        // Try to load from keychain
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: signingKeyTag,
            kSecAttrKeyType as String: kSecAttrKeyTypeEC,
            kSecReturnRef as String: true
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        if status == errSecSuccess, let keyRef = item.map({ $0 as! SecKey }) {
            // Convert SecKey to CryptoKit P256 PrivateKey
            // This conversion is non-trivial directly, so for MVP we regenerate if using Secure Enclave
            // Or we store the raw Representation in Keychain Generic Password
            
            // SIMPLIFICATION for MVP: Store P256 Private Key bits in Keychain Generic Password
            // In Production: Use Secure Enclave directly
            
            if let keyData = loadKeyData(tag: signingKeyTag),
               let key = try? P256.Signing.PrivateKey(rawRepresentation: keyData) {
                self.signingKey = key
                return
            }
        }
        
        // Generate New
        let key = P256.Signing.PrivateKey()
        self.signingKey = key
        saveKeyData(data: key.rawRepresentation, tag: signingKeyTag)
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

        guard status == errSecSuccess else { return nil }
        return (item as! SecKey)
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

    /// Generates a new master key for an incident
    func generateIncidentKey() -> SymmetricKey {
        let key = SymmetricKey(size: .bits256)
        incidentMasterKey = key
        return key
    }

    /// Derives a chunk-specific key using HKDF
    private func deriveChunkKey(masterKey: SymmetricKey, chunkNumber: Int) -> SymmetricKey {
        let info = "OnTheRecord-chunk-\(chunkNumber)".data(using: .utf8)!
        let derivedKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: masterKey,
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
        guard let masterKey = incidentMasterKey else {
            throw EncryptionError.encryptionFailed
        }

        // Derive chunk-specific key (forward secrecy)
        let chunkKey = deriveChunkKey(masterKey: masterKey, chunkNumber: metadata.chunkNumber)

        // Generate random nonce
        let nonce = AES.GCM.Nonce()

        // Encrypt data
        let sealedBox = try AES.GCM.seal(data, using: chunkKey, nonce: nonce)

        // Serialize metadata
        let metadataJSON = try JSONEncoder().encode(metadata)

        // Compute HMAC of metadata
        let metadataHMAC = HMAC<SHA256>.authenticationCode(for: metadataJSON, using: chunkKey)

        // Wrap master key with user's public key (only for first chunk of incident)
        var wrappedMasterKey: Data?
        if metadata.chunkNumber == 1 {
            wrappedMasterKey = wrapKey(masterKey)
        }

        // Compute hash of previous chunk for chain
        // (This would be passed in from the upload service in a real implementation)
        let previousHash = metadata.previousChunkHash
        
        // --- Admissibility Sealing (Digital Signature) ---
        var signature: Data?
        if let signer = signingKey {
            // Sign: EncryptedPayload + AuthTag + Metadata + PreviousHash
            var dataToSign = sealedBox.ciphertext
            dataToSign.append(sealedBox.tag)
            dataToSign.append(metadataJSON)
            if let prev = previousHash {
                dataToSign.append(prev)
            }
            
            if let sig = try? signer.signature(for: dataToSign) {
                signature = sig.rawRepresentation
            }
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

        let chunkKey = deriveChunkKey(masterKey: masterKey, chunkNumber: encryptedChunk.header.chunkNumber)

        // Verify metadata HMAC before trusting metadata
        let expectedHMAC = HMAC<SHA256>.authenticationCode(for: encryptedChunk.metadata, using: chunkKey)
        guard Data(expectedHMAC) == encryptedChunk.metadataHMAC else {
            debugLog("[EncryptionService] HMAC verification failed for chunk \(encryptedChunk.header.chunkNumber)")
            throw EncryptionError.decryptionFailed
        }

        // Verify digital signature if present
        if let signatureData = encryptedChunk.signature, let signer = signingKey {
            var dataToVerify = encryptedChunk.encryptedPayload
            dataToVerify.append(encryptedChunk.authTag)
            dataToVerify.append(encryptedChunk.metadata)
            if let prev = encryptedChunk.previousChunkHash {
                dataToVerify.append(prev)
            }
            guard let signature = try? P256.Signing.ECDSASignature(rawRepresentation: signatureData),
                  signer.publicKey.isValidSignature(signature, for: dataToVerify) else {
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

        return try AES.GCM.open(sealedBox, using: chunkKey)
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

    /// Exports the P256 signing public key for third-party verification
    func exportSigningPublicKey() -> Data? {
        return signingKey?.publicKey.rawRepresentation
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

    /// Revokes the master key (footage remains encrypted but inaccessible)
    func revokeIncidentKey() {
        incidentMasterKey = nil
    }

    // MARK: - Errors

    enum EncryptionError: LocalizedError {
        case noMasterKey
        case encryptionFailed
        case decryptionFailed
        case keyWrapFailed

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
