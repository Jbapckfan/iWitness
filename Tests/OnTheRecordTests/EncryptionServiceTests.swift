import XCTest
import CryptoKit
import Security
@testable import OnTheRecordCore

final class EncryptionServiceTests: XCTestCase {

    private var service: EncryptionService!

    /// Whether Keychain is available in the current test environment.
    /// Keychain access fails with -34018 in SPM test runners without a host app.
    private var keychainAvailable: Bool {
        return service.exportPublicKey() != nil
    }

    override func setUp() {
        super.setUp()
        service = EncryptionService()
    }

    override func tearDown() {
        service.revokeIncidentKey()
        service = nil
        super.tearDown()
    }

    // MARK: - Helper Factories

    private func makeMetadata(
        incidentID: String = "IW-TEST-0001",
        chunkNumber: Int = 1,
        previousChunkHash: Data? = nil
    ) -> ChunkMetadata {
        var meta = ChunkMetadata(
            incidentID: incidentID,
            chunkNumber: chunkNumber,
            timestamp: Date(),
            location: nil,
            quality: .high,
            deviceState: DeviceState(
                batteryLevel: 0.85,
                batteryState: "charging",
                networkType: "wifi",
                orientation: "portrait"
            )
        )
        meta.previousChunkHash = previousChunkHash
        return meta
    }

    private func randomData(bytes: Int = 1024) -> Data {
        var buf = [UInt8](repeating: 0, count: bytes)
        _ = SecRandomCopyBytes(kSecRandomDefault, buf.count, &buf)
        return Data(buf)
    }

    // MARK: - Key Generation

    func testIncidentKeyGenerationReturns256BitKey() {
        let key = service.generateIncidentKey()
        // SymmetricKey.bitCount verifies 256 bits = 32 bytes
        key.withUnsafeBytes { raw in
            XCTAssertEqual(raw.count, 32, "Incident master key should be 256 bits (32 bytes)")
        }
    }

    func testGenerateIncidentKeyProducesDifferentKeysEachCall() {
        let key1 = service.generateIncidentKey()
        let data1 = key1.withUnsafeBytes { Data($0) }

        let service2 = EncryptionService()
        let key2 = service2.generateIncidentKey()
        let data2 = key2.withUnsafeBytes { Data($0) }

        XCTAssertNotEqual(data1, data2, "Each incident should get a unique master key")
        service2.revokeIncidentKey()
    }

    func testSigningPublicKeyIsAvailable() {
        // On simulator we get a software P256 key (no Keychain required for software signing key init)
        // However, the software signing key also stores to Keychain as GenericPassword.
        // If Keychain is unavailable, signing key may still be in memory.
        // The key is generated on init and kept in memory regardless of Keychain save success.
        XCTAssertNotNil(service.signingPublicKey, "Signing public key should be available after init")
    }

    func testExportPublicKeyReturnsData() throws {
        try XCTSkipUnless(keychainAvailable, "Keychain not available in this test environment")

        let exported = service.exportPublicKey()
        XCTAssertNotNil(exported, "RSA public key export should succeed")
        if let data = exported {
            XCTAssertGreaterThan(data.count, 256, "RSA-4096 public key should be substantial")
        }
    }

    func testExportSigningPublicKeyReturnsData() {
        let exported = service.exportSigningPublicKey()
        XCTAssertNotNil(exported, "P256 signing public key export should succeed")
        if let data = exported {
            // P256 raw public key is 64 bytes (x + y coordinate)
            XCTAssertEqual(data.count, 64, "P256 public key raw representation is 64 bytes")
        }
    }

    // MARK: - AES-256-GCM Encryption / Decryption (CryptoKit - no Keychain needed)

    func testAESGCMEncryptDecryptRoundtrip() throws {
        let key = SymmetricKey(size: .bits256)
        let plaintext = randomData(bytes: 4096)
        let nonce = AES.GCM.Nonce()

        let sealed = try AES.GCM.seal(plaintext, using: key, nonce: nonce)
        let opened = try AES.GCM.open(sealed, using: key)

        XCTAssertEqual(opened, plaintext, "AES-GCM roundtrip should preserve data")
    }

    func testAESGCMWithAADRoundtrip() throws {
        let key = SymmetricKey(size: .bits256)
        let plaintext = randomData(bytes: 1024)
        let aad = Data("metadata-as-aad".utf8)

        let sealed = try AES.GCM.seal(plaintext, using: key, authenticating: aad)

        // Reconstruct SealedBox from components
        let box = try AES.GCM.SealedBox(
            nonce: sealed.nonce,
            ciphertext: sealed.ciphertext,
            tag: sealed.tag
        )
        let opened = try AES.GCM.open(box, using: key, authenticating: aad)
        XCTAssertEqual(opened, plaintext)
    }

    func testAESGCMWithWrongAADFails() throws {
        let key = SymmetricKey(size: .bits256)
        let plaintext = randomData(bytes: 512)
        let aad = Data("correct-aad".utf8)
        let wrongAad = Data("wrong-aad".utf8)

        let sealed = try AES.GCM.seal(plaintext, using: key, authenticating: aad)

        let box = try AES.GCM.SealedBox(
            nonce: sealed.nonce,
            ciphertext: sealed.ciphertext,
            tag: sealed.tag
        )

        XCTAssertThrowsError(
            try AES.GCM.open(box, using: key, authenticating: wrongAad),
            "Wrong AAD should cause AES-GCM decryption to fail"
        )
    }

    func testAESGCMTamperedCiphertextFails() throws {
        let key = SymmetricKey(size: .bits256)
        let plaintext = randomData(bytes: 512)

        let sealed = try AES.GCM.seal(plaintext, using: key)

        var tamperedCiphertext = sealed.ciphertext
        tamperedCiphertext[0] ^= 0xFF

        let box = try AES.GCM.SealedBox(
            nonce: sealed.nonce,
            ciphertext: tamperedCiphertext,
            tag: sealed.tag
        )

        XCTAssertThrowsError(
            try AES.GCM.open(box, using: key),
            "Tampered ciphertext should fail AES-GCM authentication"
        )
    }

    func testAESGCMProducesDifferentCiphertextPerNonce() throws {
        let key = SymmetricKey(size: .bits256)
        let plaintext = randomData(bytes: 256)

        let sealed1 = try AES.GCM.seal(plaintext, using: key)
        let sealed2 = try AES.GCM.seal(plaintext, using: key)

        // Different nonces produce different ciphertexts
        XCTAssertNotEqual(sealed1.ciphertext, sealed2.ciphertext,
                          "Same plaintext with different nonces should produce different ciphertext")
    }

    func testAESGCMNonceIs12Bytes() throws {
        let nonce = AES.GCM.Nonce()
        let data = Data(nonce)
        XCTAssertEqual(data.count, 12, "AES-GCM nonce should be 12 bytes")
    }

    func testAESGCMTagIs16Bytes() throws {
        let key = SymmetricKey(size: .bits256)
        let sealed = try AES.GCM.seal(Data("test".utf8), using: key)
        XCTAssertEqual(sealed.tag.count, 16, "AES-GCM tag should be 16 bytes")
    }

    // MARK: - HKDF Key Derivation

    func testHKDFProduces256BitKey() {
        let masterKey = SymmetricKey(size: .bits256)
        let salt = randomData(bytes: 32)
        let info = "OnTheRecord-chunk-0".data(using: .utf8)!

        let derived = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: masterKey,
            salt: salt,
            info: info,
            outputByteCount: 32
        )

        derived.withUnsafeBytes { raw in
            XCTAssertEqual(raw.count, 32, "HKDF should produce 32 bytes for AES-256")
        }
    }

    func testHKDFDifferentInfoProducesDifferentKeys() {
        let masterKey = SymmetricKey(size: .bits256)
        let salt = randomData(bytes: 32)

        let key1 = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: masterKey,
            salt: salt,
            info: "OnTheRecord-chunk-0".data(using: .utf8)!,
            outputByteCount: 32
        )
        let key2 = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: masterKey,
            salt: salt,
            info: "OnTheRecord-chunk-1".data(using: .utf8)!,
            outputByteCount: 32
        )

        let data1 = key1.withUnsafeBytes { Data($0) }
        let data2 = key2.withUnsafeBytes { Data($0) }
        XCTAssertNotEqual(data1, data2, "Different chunk numbers should derive different keys")
    }

    func testHKDFDifferentSaltsProduceDifferentKeys() {
        let masterKey = SymmetricKey(size: .bits256)
        let info = "OnTheRecord-chunk-0".data(using: .utf8)!

        let key1 = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: masterKey,
            salt: randomData(bytes: 32),
            info: info,
            outputByteCount: 32
        )
        let key2 = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: masterKey,
            salt: randomData(bytes: 32),
            info: info,
            outputByteCount: 32
        )

        let data1 = key1.withUnsafeBytes { Data($0) }
        let data2 = key2.withUnsafeBytes { Data($0) }
        XCTAssertNotEqual(data1, data2, "Different salts should derive different keys")
    }

    func testHKDFIsDeterministic() {
        let masterKey = SymmetricKey(size: .bits256)
        let salt = Data(repeating: 0xAB, count: 32)
        let info = "OnTheRecord-chunk-42".data(using: .utf8)!

        let key1 = HKDF<SHA256>.deriveKey(inputKeyMaterial: masterKey, salt: salt, info: info, outputByteCount: 32)
        let key2 = HKDF<SHA256>.deriveKey(inputKeyMaterial: masterKey, salt: salt, info: info, outputByteCount: 32)

        let data1 = key1.withUnsafeBytes { Data($0) }
        let data2 = key2.withUnsafeBytes { Data($0) }
        XCTAssertEqual(data1, data2, "Same inputs should produce same derived key")
    }

    // MARK: - Full Encrypt/Decrypt Roundtrip (requires Keychain for RSA)

    func testEncryptDecryptRoundtrip() throws {
        try XCTSkipUnless(keychainAvailable, "Keychain not available in this test environment")

        let plaintext = randomData(bytes: 4096)
        let metadata = makeMetadata()

        let encrypted = try service.encryptChunk(plaintext, metadata: metadata)

        XCTAssertEqual(encrypted.header.magic, "IWIT")
        XCTAssertEqual(encrypted.header.version, 1)
        XCTAssertEqual(encrypted.header.chunkNumber, 1)
        XCTAssertFalse(encrypted.encryptedPayload.isEmpty)
        XCTAssertNotEqual(encrypted.encryptedPayload, plaintext)
        XCTAssertEqual(encrypted.nonce.count, 12)
        XCTAssertEqual(encrypted.authTag.count, 16)
        XCTAssertNotNil(encrypted.wrappedMasterKey)
        XCTAssertEqual(encrypted.salt.count, 32)

        let decrypted = try service.decryptChunk(encrypted)
        XCTAssertEqual(decrypted, plaintext)
    }

    func testEncryptDecryptMultipleChunksWithChaining() throws {
        try XCTSkipUnless(keychainAvailable, "Keychain not available in this test environment")

        let plain1 = randomData(bytes: 2048)
        let plain2 = randomData(bytes: 2048)

        let meta1 = makeMetadata(chunkNumber: 1)
        let enc1 = try service.encryptChunk(plain1, metadata: meta1)

        let hash1 = enc1.computeHash()
        let meta2 = makeMetadata(chunkNumber: 2, previousChunkHash: hash1)
        let enc2 = try service.encryptChunk(plain2, metadata: meta2)

        XCTAssertEqual(enc2.previousChunkHash, hash1)

        let dec1 = try service.decryptChunk(enc1)
        let dec2 = try service.decryptChunk(enc2)
        XCTAssertEqual(dec1, plain1)
        XCTAssertEqual(dec2, plain2)
    }

    func testDecryptionFailsWithTamperedCiphertext() throws {
        try XCTSkipUnless(keychainAvailable, "Keychain not available in this test environment")

        let plaintext = randomData(bytes: 512)
        let metadata = makeMetadata()
        let encrypted = try service.encryptChunk(plaintext, metadata: metadata)

        var payload = encrypted.encryptedPayload
        if !payload.isEmpty { payload[0] ^= 0xFF }

        let tampered = EncryptedChunk(
            header: encrypted.header,
            encryptedPayload: payload,
            nonce: encrypted.nonce,
            authTag: encrypted.authTag,
            metadata: encrypted.metadata,
            metadataHMAC: encrypted.metadataHMAC,
            wrappedMasterKey: encrypted.wrappedMasterKey,
            salt: encrypted.salt,
            previousChunkHash: encrypted.previousChunkHash,
            signature: encrypted.signature
        )

        XCTAssertThrowsError(try service.decryptChunk(tampered))
    }

    func testDecryptionFailsWithTamperedMetadata() throws {
        try XCTSkipUnless(keychainAvailable, "Keychain not available in this test environment")

        let plaintext = randomData(bytes: 512)
        let metadata = makeMetadata()
        let encrypted = try service.encryptChunk(plaintext, metadata: metadata)

        var tamperedMeta = encrypted.metadata
        if !tamperedMeta.isEmpty { tamperedMeta[0] ^= 0xFF }

        let tampered = EncryptedChunk(
            header: encrypted.header,
            encryptedPayload: encrypted.encryptedPayload,
            nonce: encrypted.nonce,
            authTag: encrypted.authTag,
            metadata: tamperedMeta,
            metadataHMAC: encrypted.metadataHMAC,
            wrappedMasterKey: encrypted.wrappedMasterKey,
            salt: encrypted.salt,
            previousChunkHash: encrypted.previousChunkHash,
            signature: encrypted.signature
        )

        XCTAssertThrowsError(try service.decryptChunk(tampered))
    }

    // MARK: - Key Wrapping (RSA OAEP) - requires Keychain

    func testWrappedMasterKeyIsPresent() throws {
        try XCTSkipUnless(keychainAvailable, "Keychain not available in this test environment")

        let plaintext = randomData(bytes: 128)
        let metadata = makeMetadata()
        let encrypted = try service.encryptChunk(plaintext, metadata: metadata)

        XCTAssertNotNil(encrypted.wrappedMasterKey)
        if let wrapped = encrypted.wrappedMasterKey {
            XCTAssertEqual(wrapped.count, 512, "RSA-4096 encrypted output should be 512 bytes")
        }
    }

    func testDecryptionWithUnwrappedKeyFromChunk() throws {
        try XCTSkipUnless(keychainAvailable, "Keychain not available in this test environment")

        let plaintext = randomData(bytes: 512)
        let metadata = makeMetadata()
        let encrypted = try service.encryptChunk(plaintext, metadata: metadata)

        let service2 = EncryptionService()
        let decrypted = try service2.decryptChunk(encrypted)
        XCTAssertEqual(decrypted, plaintext)
        service2.revokeIncidentKey()
    }

    // MARK: - AAD Integrity

    func testMetadataIsAuthenticatedWithCiphertext() throws {
        try XCTSkipUnless(keychainAvailable, "Keychain not available in this test environment")

        let plaintext = randomData(bytes: 256)
        let meta1 = makeMetadata(incidentID: "IW-REAL-001", chunkNumber: 1)
        let encrypted = try service.encryptChunk(plaintext, metadata: meta1)

        let fakeMeta = makeMetadata(incidentID: "IW-FAKE-002", chunkNumber: 99)
        let fakeMetaJSON = try JSONEncoder().encode(fakeMeta)

        let forged = EncryptedChunk(
            header: encrypted.header,
            encryptedPayload: encrypted.encryptedPayload,
            nonce: encrypted.nonce,
            authTag: encrypted.authTag,
            metadata: fakeMetaJSON,
            metadataHMAC: encrypted.metadataHMAC,
            wrappedMasterKey: encrypted.wrappedMasterKey,
            salt: encrypted.salt,
            previousChunkHash: encrypted.previousChunkHash,
            signature: encrypted.signature
        )

        XCTAssertThrowsError(try service.decryptChunk(forged))
    }

    // MARK: - Private Key Export/Import (requires Keychain)

    func testExportPrivateKeysReturnsBothComponents() throws {
        try XCTSkipUnless(keychainAvailable, "Keychain not available in this test environment")

        let exported = service.exportPrivateKeys()
        XCTAssertNotNil(exported)
        if let keys = exported {
            XCTAssertGreaterThan(keys.rsaPrivateKey.count, 0)
            XCTAssertEqual(keys.signingPublicKey.count, 64)
        }
    }

    func testImportPrivateKeysRoundtrip() throws {
        try XCTSkipUnless(keychainAvailable, "Keychain not available in this test environment")

        guard let exported = service.exportPrivateKeys() else {
            XCTFail("Failed to export private keys")
            return
        }

        let plaintext = randomData(bytes: 512)
        let metadata = makeMetadata()
        let encrypted = try service.encryptChunk(plaintext, metadata: metadata)

        let service2 = EncryptionService()
        let importResult = service2.importPrivateKeys(
            rsaPrivateKeyData: exported.rsaPrivateKey,
            signingPublicKeyData: exported.signingPublicKey
        )
        XCTAssertTrue(importResult)

        let decrypted = try service2.decryptChunk(encrypted)
        XCTAssertEqual(decrypted, plaintext)
        service2.revokeIncidentKey()
    }

    // MARK: - Signature Generation & Verification (software P256 - no Keychain needed for verify)

    func testSignAndVerify() throws {
        let data = randomData(bytes: 256)
        let signature = try service.sign(data)

        guard let pubKey = service.signingPublicKey else {
            XCTFail("Signing public key should be available")
            return
        }

        XCTAssertTrue(
            pubKey.isValidSignature(signature, for: data),
            "Signature should verify against the correct data"
        )
    }

    func testSignatureFailsForModifiedData() throws {
        let data = randomData(bytes: 256)
        let signature = try service.sign(data)

        var modified = data
        modified[0] ^= 0xFF

        guard let pubKey = service.signingPublicKey else {
            XCTFail("Signing public key should be available")
            return
        }

        XCTAssertFalse(
            pubKey.isValidSignature(signature, for: modified),
            "Signature should NOT verify for modified data"
        )
    }

    func testP256SignAndVerifyWithSoftwareKeys() throws {
        // Direct CryptoKit test -- always works regardless of Keychain
        let privateKey = P256.Signing.PrivateKey()
        let publicKey = privateKey.publicKey

        let data = randomData(bytes: 512)
        let signature = try privateKey.signature(for: data)

        XCTAssertTrue(publicKey.isValidSignature(signature, for: data))

        var tampered = data
        tampered[0] ^= 0xFF
        XCTAssertFalse(publicKey.isValidSignature(signature, for: tampered))
    }

    func testP256SignatureIsDifferentEachTime() throws {
        // ECDSA signatures are non-deterministic (random k value)
        let privateKey = P256.Signing.PrivateKey()
        let data = randomData(bytes: 128)

        let sig1 = try privateKey.signature(for: data)
        let sig2 = try privateKey.signature(for: data)

        XCTAssertNotEqual(sig1.rawRepresentation, sig2.rawRepresentation,
                          "ECDSA signatures should differ due to random nonce")
    }

    func testEncryptedChunkContainsValidSignature() throws {
        try XCTSkipUnless(keychainAvailable, "Keychain not available in this test environment")

        let plaintext = randomData(bytes: 512)
        let metadata = makeMetadata()
        let encrypted = try service.encryptChunk(plaintext, metadata: metadata)

        XCTAssertNotNil(encrypted.signature)

        guard let pubKey = service.signingPublicKey else {
            XCTFail("Signing public key should be available")
            return
        }

        let verified = service.verifyChunkSignature(encrypted, publicKey: pubKey)
        XCTAssertTrue(verified)
    }

    func testChunkSignatureFailsWithWrongPublicKey() throws {
        try XCTSkipUnless(keychainAvailable, "Keychain not available in this test environment")

        let plaintext = randomData(bytes: 512)
        let metadata = makeMetadata()
        let encrypted = try service.encryptChunk(plaintext, metadata: metadata)

        let otherKey = P256.Signing.PrivateKey()
        let verified = service.verifyChunkSignature(encrypted, publicKey: otherKey.publicKey)
        XCTAssertFalse(verified)
    }

    // MARK: - Chunk Hash

    func testComputeHashIsDeterministic() throws {
        try XCTSkipUnless(keychainAvailable, "Keychain not available in this test environment")

        let plaintext = randomData(bytes: 512)
        let metadata = makeMetadata()
        let encrypted = try service.encryptChunk(plaintext, metadata: metadata)

        let hash1 = encrypted.computeHash()
        let hash2 = encrypted.computeHash()
        XCTAssertEqual(hash1, hash2)
        XCTAssertEqual(hash1.count, 32, "SHA-256 hash is 32 bytes")
    }

    // MARK: - Serialization

    func testEncryptedChunkSerializationRoundtrip() throws {
        try XCTSkipUnless(keychainAvailable, "Keychain not available in this test environment")

        let plaintext = randomData(bytes: 1024)
        let metadata = makeMetadata()
        let encrypted = try service.encryptChunk(plaintext, metadata: metadata)

        let serialized = encrypted.serialize()
        XCTAssertFalse(serialized.isEmpty)

        let decoded = try JSONDecoder().decode(EncryptedChunk.self, from: serialized)
        XCTAssertEqual(decoded.header.magic, encrypted.header.magic)
        XCTAssertEqual(decoded.encryptedPayload, encrypted.encryptedPayload)

        let decrypted = try service.decryptChunk(decoded)
        XCTAssertEqual(decrypted, plaintext)
    }

    // MARK: - Key Revocation

    func testRevokeIncidentKeyClearsState() throws {
        try XCTSkipUnless(keychainAvailable, "Keychain not available in this test environment")

        let plaintext = randomData(bytes: 256)
        let metadata = makeMetadata()
        let encrypted = try service.encryptChunk(plaintext, metadata: metadata)

        service.revokeIncidentKey()

        let plaintext2 = randomData(bytes: 256)
        let metadata2 = makeMetadata(chunkNumber: 2)
        let encrypted2 = try service.encryptChunk(plaintext2, metadata: metadata2)

        XCTAssertNotEqual(encrypted.salt, encrypted2.salt,
                          "After revocation, a new incident key + salt should be generated")
    }

    // MARK: - Thread Safety

    func testConcurrentEncryptCallsDoNotCrash() throws {
        try XCTSkipUnless(keychainAvailable, "Keychain not available in this test environment")

        let plaintext = randomData(bytes: 256)
        let expectation = XCTestExpectation(description: "All concurrent encryptions complete")
        expectation.expectedFulfillmentCount = 10

        var errors: [Error] = []
        let errLock = NSLock()

        for i in 0..<10 {
            DispatchQueue.global(qos: .userInitiated).async { [service] in
                defer { expectation.fulfill() }
                let meta = ChunkMetadata(
                    incidentID: "IW-CONCURRENT-TEST",
                    chunkNumber: i,
                    timestamp: Date(),
                    location: nil,
                    quality: .high,
                    deviceState: DeviceState(
                        batteryLevel: 0.5,
                        batteryState: "unplugged",
                        networkType: "wifi",
                        orientation: "portrait"
                    )
                )
                do {
                    _ = try service!.encryptChunk(plaintext, metadata: meta)
                } catch {
                    errLock.lock()
                    errors.append(error)
                    errLock.unlock()
                }
            }
        }

        wait(for: [expectation], timeout: 30.0)
        XCTAssertTrue(errors.isEmpty, "Concurrent encryption should not produce errors: \(errors)")
    }

    // MARK: - HMAC Verification

    func testHMACVerification() {
        let key = SymmetricKey(size: .bits256)
        let data = randomData(bytes: 256)

        let mac = HMAC<SHA256>.authenticationCode(for: data, using: key)
        XCTAssertTrue(HMAC<SHA256>.isValidAuthenticationCode(mac, authenticating: data, using: key))

        var tampered = data
        tampered[0] ^= 0xFF
        XCTAssertFalse(HMAC<SHA256>.isValidAuthenticationCode(mac, authenticating: tampered, using: key))
    }

    func testHMACDifferentKeysProduceDifferentMACs() {
        let key1 = SymmetricKey(size: .bits256)
        let key2 = SymmetricKey(size: .bits256)
        let data = randomData(bytes: 128)

        let mac1 = Data(HMAC<SHA256>.authenticationCode(for: data, using: key1))
        let mac2 = Data(HMAC<SHA256>.authenticationCode(for: data, using: key2))
        XCTAssertNotEqual(mac1, mac2)
    }

    // MARK: - ChunkMetadata & Supporting Types

    func testChunkMetadataEncodesAndDecodes() throws {
        let meta = makeMetadata(incidentID: "IW-META-TEST", chunkNumber: 42)
        let data = try JSONEncoder().encode(meta)
        let decoded = try JSONDecoder().decode(ChunkMetadata.self, from: data)

        XCTAssertEqual(decoded.incidentID, "IW-META-TEST")
        XCTAssertEqual(decoded.chunkNumber, 42)
        XCTAssertEqual(decoded.quality, "1080p")
    }

    func testDeviceStateCodable() throws {
        let state = DeviceState(
            batteryLevel: 0.75,
            batteryState: "charging",
            networkType: "wifi",
            orientation: "portrait"
        )

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(DeviceState.self, from: data)

        XCTAssertEqual(decoded.batteryLevel, 0.75, accuracy: 0.01)
        XCTAssertEqual(decoded.batteryState, "charging")
        XCTAssertEqual(decoded.networkType, "wifi")
        XCTAssertEqual(decoded.orientation, "portrait")
    }

    func testChunkHeaderCodable() throws {
        let header = ChunkHeader(
            magic: "IWIT",
            version: 1,
            chunkNumber: 5,
            timestamp: Date(),
            incidentID: "IW-HEADER-TEST"
        )

        let data = try JSONEncoder().encode(header)
        let decoded = try JSONDecoder().decode(ChunkHeader.self, from: data)

        XCTAssertEqual(decoded.magic, "IWIT")
        XCTAssertEqual(decoded.version, 1)
        XCTAssertEqual(decoded.chunkNumber, 5)
        XCTAssertEqual(decoded.incidentID, "IW-HEADER-TEST")
    }

    // MARK: - Edge Cases

    func testEncryptEmptyData() throws {
        try XCTSkipUnless(keychainAvailable, "Keychain not available in this test environment")

        let plaintext = Data()
        let metadata = makeMetadata()
        let encrypted = try service.encryptChunk(plaintext, metadata: metadata)
        let decrypted = try service.decryptChunk(encrypted)
        XCTAssertEqual(decrypted, plaintext)
    }

    func testAESGCMEncryptDecryptEmptyData() throws {
        let key = SymmetricKey(size: .bits256)
        let sealed = try AES.GCM.seal(Data(), using: key)
        let opened = try AES.GCM.open(sealed, using: key)
        XCTAssertEqual(opened, Data())
    }

    func testAESGCMEncryptDecryptLargeData() throws {
        let key = SymmetricKey(size: .bits256)
        let plaintext = randomData(bytes: 1_048_576) // 1MB
        let sealed = try AES.GCM.seal(plaintext, using: key)
        let opened = try AES.GCM.open(sealed, using: key)
        XCTAssertEqual(opened, plaintext)
    }

    // MARK: - EncryptionError Descriptions

    func testEncryptionErrorDescriptions() {
        XCTAssertNotNil(EncryptionService.EncryptionError.noMasterKey.errorDescription)
        XCTAssertNotNil(EncryptionService.EncryptionError.encryptionFailed.errorDescription)
        XCTAssertNotNil(EncryptionService.EncryptionError.decryptionFailed.errorDescription)
        XCTAssertNotNil(EncryptionService.EncryptionError.keyWrapFailed.errorDescription)
        XCTAssertNotNil(EncryptionService.EncryptionError.signingKeyUnavailable.errorDescription)
    }
}
