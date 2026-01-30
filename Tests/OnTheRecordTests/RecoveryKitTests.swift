import XCTest
import CryptoKit
import Security
@testable import OnTheRecordCore

final class RecoveryKitTests: XCTestCase {

    private var recoveryService: RecoveryKitService!
    private var encryptionService: EncryptionService!

    /// Whether Keychain is available (RSA keys require Keychain access).
    /// RecoveryKit depends on Keychain to export private keys.
    private var keychainAvailable: Bool {
        return encryptionService.exportPublicKey() != nil
    }

    override func setUp() {
        super.setUp()
        recoveryService = RecoveryKitService.shared
        encryptionService = EncryptionService()
    }

    override func tearDown() {
        encryptionService = nil
        super.tearDown()
    }

    // MARK: - Recovery Code Generation (format tests - no Keychain needed)

    /// Tests the recovery code format using direct string generation logic.
    /// The code format is XXXXX-XXXXX-XXXXX-XXXXX using chars ABCDEFGHJKLMNPQRSTUVWXYZ23456789
    func testRecoveryCodeFormatViaKitCreation() throws {
        try XCTSkipUnless(keychainAvailable, "Keychain not available in this test environment")

        guard let result = recoveryService.createRecoveryKit() else {
            XCTFail("createRecoveryKit should succeed when keys exist")
            return
        }

        let code = result.code
        let groups = code.split(separator: "-")
        XCTAssertEqual(groups.count, 4, "Recovery code should have 4 groups")

        for group in groups {
            XCTAssertEqual(group.count, 5, "Each group should have 5 characters")
        }

        let stripped = code.replacingOccurrences(of: "-", with: "")
        XCTAssertEqual(stripped.count, 20, "Code should be 20 chars without dashes")

        let validChars = CharacterSet(charactersIn: "ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        for char in stripped.unicodeScalars {
            XCTAssertTrue(validChars.contains(char), "Invalid character '\(char)' in code")
        }
    }

    func testRecoveryCodeUniqueness() throws {
        try XCTSkipUnless(keychainAvailable, "Keychain not available in this test environment")

        var codes = Set<String>()
        for _ in 0..<5 {
            guard let result = recoveryService.createRecoveryKit() else {
                XCTFail("createRecoveryKit should succeed")
                continue
            }
            codes.insert(result.code)
        }
        XCTAssertEqual(codes.count, 5, "All recovery codes should be unique")
    }

    func testRecoveryCodeDoesNotContainConfusingCharacters() throws {
        try XCTSkipUnless(keychainAvailable, "Keychain not available in this test environment")

        guard let result = recoveryService.createRecoveryKit() else {
            XCTFail("createRecoveryKit should succeed")
            return
        }

        let stripped = result.code.replacingOccurrences(of: "-", with: "")
        let confusing = CharacterSet(charactersIn: "0O1I")
        for char in stripped.unicodeScalars {
            XCTAssertFalse(confusing.contains(char), "Code should not contain '\(char)'")
        }
    }

    // MARK: - Recovery Kit Structure

    func testRecoveryKitHasCorrectVersion() throws {
        try XCTSkipUnless(keychainAvailable, "Keychain not available in this test environment")

        guard let result = recoveryService.createRecoveryKit() else {
            XCTFail("createRecoveryKit should succeed")
            return
        }
        XCTAssertEqual(result.kit.version, 1)
    }

    func testRecoveryKitHasNonEmptyPayload() throws {
        try XCTSkipUnless(keychainAvailable, "Keychain not available in this test environment")

        guard let result = recoveryService.createRecoveryKit() else {
            XCTFail("createRecoveryKit should succeed")
            return
        }

        XCTAssertFalse(result.kit.encryptedPayload.isEmpty)
        XCTAssertEqual(result.kit.salt.count, 32)
        XCTAssertFalse(result.kit.nonce.isEmpty)
        XCTAssertFalse(result.kit.deviceName.isEmpty)
    }

    // MARK: - Create / Import Roundtrip

    func testCreateAndImportRecoveryKitRoundtrip() throws {
        try XCTSkipUnless(keychainAvailable, "Keychain not available in this test environment")

        guard let result = recoveryService.createRecoveryKit() else {
            XCTFail("createRecoveryKit should succeed")
            return
        }

        let imported = recoveryService.importRecoveryKit(result.kit, recoveryCode: result.code)
        XCTAssertTrue(imported, "Importing with the correct code should succeed")
    }

    // MARK: - Wrong Recovery Code Rejection

    func testImportWithWrongCodeFails() throws {
        try XCTSkipUnless(keychainAvailable, "Keychain not available in this test environment")

        guard let result = recoveryService.createRecoveryKit() else {
            XCTFail("createRecoveryKit should succeed")
            return
        }

        let wrongCode = "AAAAA-BBBBB-CCCCC-DDDDD"
        let imported = recoveryService.importRecoveryKit(result.kit, recoveryCode: wrongCode)
        XCTAssertFalse(imported, "Wrong code should fail")
    }

    func testImportWithPartiallyWrongCodeFails() throws {
        try XCTSkipUnless(keychainAvailable, "Keychain not available in this test environment")

        guard let result = recoveryService.createRecoveryKit() else {
            XCTFail("createRecoveryKit should succeed")
            return
        }

        var chars = Array(result.code)
        for i in 0..<chars.count {
            if chars[i] != "-" {
                chars[i] = (chars[i] == "A") ? "B" : "A"
                break
            }
        }
        let almostRight = String(chars)
        let imported = recoveryService.importRecoveryKit(result.kit, recoveryCode: almostRight)
        XCTAssertFalse(imported, "Even one wrong character should fail")
    }

    func testImportWithEmptyCodeFails() throws {
        try XCTSkipUnless(keychainAvailable, "Keychain not available in this test environment")

        guard let result = recoveryService.createRecoveryKit() else {
            XCTFail("createRecoveryKit should succeed")
            return
        }

        let imported = recoveryService.importRecoveryKit(result.kit, recoveryCode: "")
        XCTAssertFalse(imported, "Empty code should fail")
    }

    // MARK: - File Export / Import Roundtrip

    func testFileExportImportRoundtrip() throws {
        try XCTSkipUnless(keychainAvailable, "Keychain not available in this test environment")

        guard let result = recoveryService.createRecoveryKit() else {
            XCTFail("createRecoveryKit should succeed")
            return
        }

        guard let fileData = recoveryService.exportToFile(result.kit) else {
            XCTFail("Export to file should succeed")
            return
        }
        XCTAssertFalse(fileData.isEmpty)

        guard let importedKit = recoveryService.importFromFile(fileData) else {
            XCTFail("Import from file should succeed")
            return
        }

        XCTAssertEqual(importedKit.version, result.kit.version)
        XCTAssertEqual(importedKit.deviceName, result.kit.deviceName)
        XCTAssertEqual(importedKit.encryptedPayload, result.kit.encryptedPayload)
        XCTAssertEqual(importedKit.nonce, result.kit.nonce)
        XCTAssertEqual(importedKit.salt, result.kit.salt)

        let restored = recoveryService.importRecoveryKit(importedKit, recoveryCode: result.code)
        XCTAssertTrue(restored, "Imported kit should restore with original code")
    }

    func testImportFromCorruptedFileDataFails() {
        let garbage = Data("this is not valid JSON at all".utf8)
        let imported = recoveryService.importFromFile(garbage)
        XCTAssertNil(imported, "Corrupted data should return nil")
    }

    func testImportFromTruncatedFileDataFails() throws {
        try XCTSkipUnless(keychainAvailable, "Keychain not available in this test environment")

        guard let result = recoveryService.createRecoveryKit() else {
            XCTFail("createRecoveryKit should succeed")
            return
        }

        guard let fileData = recoveryService.exportToFile(result.kit) else {
            XCTFail("Export should succeed")
            return
        }

        let truncated = fileData.prefix(fileData.count / 2)
        let imported = recoveryService.importFromFile(truncated)
        XCTAssertNil(imported, "Truncated data should fail import")
    }

    // MARK: - Recovery Code Normalization

    func testCodeNormalizationStripsDashes() throws {
        try XCTSkipUnless(keychainAvailable, "Keychain not available in this test environment")

        guard let result = recoveryService.createRecoveryKit() else {
            XCTFail("createRecoveryKit should succeed")
            return
        }

        let noDashes = result.code.replacingOccurrences(of: "-", with: "")
        let imported = recoveryService.importRecoveryKit(result.kit, recoveryCode: noDashes)
        XCTAssertTrue(imported, "Code without dashes should work")
    }

    func testCodeNormalizationIsCaseInsensitive() throws {
        try XCTSkipUnless(keychainAvailable, "Keychain not available in this test environment")

        guard let result = recoveryService.createRecoveryKit() else {
            XCTFail("createRecoveryKit should succeed")
            return
        }

        let lowercase = result.code.lowercased()
        let imported = recoveryService.importRecoveryKit(result.kit, recoveryCode: lowercase)
        XCTAssertTrue(imported, "Lowercase code should work")
    }

    func testCodeNormalizationWithExtraDashes() throws {
        try XCTSkipUnless(keychainAvailable, "Keychain not available in this test environment")

        guard let result = recoveryService.createRecoveryKit() else {
            XCTFail("createRecoveryKit should succeed")
            return
        }

        let extraDashes = "---" + result.code + "---"
        let imported = recoveryService.importRecoveryKit(result.kit, recoveryCode: extraDashes)
        XCTAssertTrue(imported, "Extra dashes should be stripped")
    }

    // MARK: - HKDF Key Derivation (standalone - no Keychain needed)

    func testHKDFDeriveKeyFromCodeProducesDeterministicResult() {
        let code = "ABCDE-FGHJK-LMNPQ-RSTUV"
        let salt = Data(repeating: 0x42, count: 32)
        let normalized = code.replacingOccurrences(of: "-", with: "").uppercased()
        let codeData = normalized.data(using: .utf8)!

        let key1 = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: codeData),
            salt: salt,
            info: "OnTheRecord-RecoveryKit-v1".data(using: .utf8)!,
            outputByteCount: 32
        )
        let key2 = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: codeData),
            salt: salt,
            info: "OnTheRecord-RecoveryKit-v1".data(using: .utf8)!,
            outputByteCount: 32
        )

        let data1 = key1.withUnsafeBytes { Data($0) }
        let data2 = key2.withUnsafeBytes { Data($0) }
        XCTAssertEqual(data1, data2, "Same code + salt should always derive the same key")
    }

    func testHKDFDifferentCodesProduceDifferentKeys() {
        let salt = Data(repeating: 0x42, count: 32)
        let info = "OnTheRecord-RecoveryKit-v1".data(using: .utf8)!

        let key1 = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: "ABCDEFGHJKLMNPQRSTUV".data(using: .utf8)!),
            salt: salt, info: info, outputByteCount: 32
        )
        let key2 = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: "VUTSPQNMLKJHGFEDCBA2".data(using: .utf8)!),
            salt: salt, info: info, outputByteCount: 32
        )

        let data1 = key1.withUnsafeBytes { Data($0) }
        let data2 = key2.withUnsafeBytes { Data($0) }
        XCTAssertNotEqual(data1, data2, "Different codes should derive different keys")
    }

    func testHKDFDifferentSaltsProduceDifferentKeys() {
        let codeData = "ABCDEFGHJKLMNPQRSTUV".data(using: .utf8)!
        let info = "OnTheRecord-RecoveryKit-v1".data(using: .utf8)!

        let key1 = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: codeData),
            salt: Data(repeating: 0x01, count: 32), info: info, outputByteCount: 32
        )
        let key2 = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: codeData),
            salt: Data(repeating: 0x02, count: 32), info: info, outputByteCount: 32
        )

        let data1 = key1.withUnsafeBytes { Data($0) }
        let data2 = key2.withUnsafeBytes { Data($0) }
        XCTAssertNotEqual(data1, data2, "Different salts should derive different keys")
    }

    // MARK: - AES-GCM Encrypt/Decrypt with Derived Key (standalone - no Keychain)

    func testRecoveryCodeEncryptDecryptRoundtripStandalone() throws {
        // Simulate the recovery kit flow without Keychain:
        // 1. Generate a "recovery code"
        // 2. Derive a key from the code
        // 3. Encrypt some data
        // 4. Decrypt with the same code + salt

        let code = "ABCDE-FGHJK-LMNPQ-RSTUV"
        let normalized = code.replacingOccurrences(of: "-", with: "").uppercased()
        let codeData = normalized.data(using: .utf8)!

        var saltBytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, saltBytes.count, &saltBytes)
        let salt = Data(saltBytes)

        let derivedKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: codeData),
            salt: salt,
            info: "OnTheRecord-RecoveryKit-v1".data(using: .utf8)!,
            outputByteCount: 32
        )

        let secretData = Data("Private key material goes here".utf8)
        let sealed = try AES.GCM.seal(secretData, using: derivedKey)

        // Re-derive key from same code + salt
        let derivedKey2 = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: codeData),
            salt: salt,
            info: "OnTheRecord-RecoveryKit-v1".data(using: .utf8)!,
            outputByteCount: 32
        )

        let decrypted = try AES.GCM.open(sealed, using: derivedKey2)
        XCTAssertEqual(decrypted, secretData, "Should decrypt with same code + salt")
    }

    func testRecoveryCodeWrongCodeFailsDecrypt() throws {
        let code = "ABCDE-FGHJK-LMNPQ-RSTUV"
        let wrongCode = "VUTSR-QPNML-KJHGF-EDCBA"
        let salt = Data(repeating: 0x55, count: 32)
        let info = "OnTheRecord-RecoveryKit-v1".data(using: .utf8)!

        let correctKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: code.replacingOccurrences(of: "-", with: "").data(using: .utf8)!),
            salt: salt, info: info, outputByteCount: 32
        )
        let wrongKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: wrongCode.replacingOccurrences(of: "-", with: "").data(using: .utf8)!),
            salt: salt, info: info, outputByteCount: 32
        )

        let secretData = Data("top secret".utf8)
        let sealed = try AES.GCM.seal(secretData, using: correctKey)

        XCTAssertThrowsError(
            try AES.GCM.open(sealed, using: wrongKey),
            "Wrong code should fail decryption"
        )
    }

    // MARK: - File Export Produces Valid JSON (standalone)

    func testExportProducesValidJSON() throws {
        try XCTSkipUnless(keychainAvailable, "Keychain not available in this test environment")

        guard let result = recoveryService.createRecoveryKit() else {
            XCTFail("createRecoveryKit should succeed")
            return
        }

        guard let fileData = recoveryService.exportToFile(result.kit) else {
            XCTFail("Export should succeed")
            return
        }

        let json = try? JSONSerialization.jsonObject(with: fileData)
        XCTAssertNotNil(json, "Exported file should be valid JSON")

        if let dict = json as? [String: Any] {
            XCTAssertNotNil(dict["encryptedPayload"])
            XCTAssertNotNil(dict["nonce"])
            XCTAssertNotNil(dict["salt"])
            XCTAssertNotNil(dict["deviceName"])
            XCTAssertNotNil(dict["exportDate"])
            XCTAssertNotNil(dict["version"])
        }
    }

    // MARK: - RecoveryKit Codable

    func testRecoveryKitCodableRoundtrip() throws {
        let kit = RecoveryKitService.RecoveryKit(
            encryptedPayload: Data(repeating: 0xAA, count: 256),
            nonce: Data(repeating: 0xBB, count: 12),
            salt: Data(repeating: 0xCC, count: 32),
            deviceName: "Test iPhone",
            exportDate: Date(),
            version: 1
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(kit)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(RecoveryKitService.RecoveryKit.self, from: data)

        XCTAssertEqual(decoded.encryptedPayload, kit.encryptedPayload)
        XCTAssertEqual(decoded.nonce, kit.nonce)
        XCTAssertEqual(decoded.salt, kit.salt)
        XCTAssertEqual(decoded.deviceName, kit.deviceName)
        XCTAssertEqual(decoded.version, kit.version)
    }

    // MARK: - End-to-End with Keychain

    func testRecoveryKitRestoresDecryptionCapability() throws {
        try XCTSkipUnless(keychainAvailable, "Keychain not available in this test environment")

        let plaintext = Data("Evidence data for recovery test".utf8)
        let metadata = ChunkMetadata(
            incidentID: "IW-RECOVERY-TEST",
            chunkNumber: 1,
            timestamp: Date(),
            location: nil,
            quality: .high,
            deviceState: DeviceState(
                batteryLevel: 1.0,
                batteryState: "full",
                networkType: "wifi",
                orientation: "portrait"
            )
        )
        let encrypted = try encryptionService.encryptChunk(plaintext, metadata: metadata)

        guard let result = recoveryService.createRecoveryKit() else {
            XCTFail("Should create recovery kit")
            return
        }

        let restored = recoveryService.importRecoveryKit(result.kit, recoveryCode: result.code)
        XCTAssertTrue(restored)

        let restoredService = EncryptionService()
        let decrypted = try restoredService.decryptChunk(encrypted)
        XCTAssertEqual(decrypted, plaintext)
        restoredService.revokeIncidentKey()
    }

    // MARK: - Code Normalization (standalone - no Keychain)

    func testNormalizationRemovesDashesAndUppercases() {
        let input = "abcde-fghjk-lmnpq-rstuv"
        let normalized = input.replacingOccurrences(of: "-", with: "").uppercased()
        XCTAssertEqual(normalized, "ABCDEFGHJKLMNPQRSTUV")
    }

    func testNormalizationHandlesNoDashes() {
        let input = "ABCDEFGHJKLMNPQRSTUV"
        let normalized = input.replacingOccurrences(of: "-", with: "").uppercased()
        XCTAssertEqual(normalized, "ABCDEFGHJKLMNPQRSTUV")
    }

    func testNormalizationHandlesExtraDashes() {
        let input = "---ABCDE---FGHJK---"
        let normalized = input.replacingOccurrences(of: "-", with: "").uppercased()
        XCTAssertEqual(normalized, "ABCDEFGHJK")
    }

    func testNormalizationHandlesMixedCase() {
        let input = "AbCdE-fGhJk-LmNpQ-rStUv"
        let normalized = input.replacingOccurrences(of: "-", with: "").uppercased()
        XCTAssertEqual(normalized, "ABCDEFGHJKLMNPQRSTUV")
    }
}
