import XCTest
import CryptoKit
@testable import OnTheRecordCore

@MainActor
final class TimestampAnchorTests: XCTestCase {

    private var service: TimestampAnchorService!
    private let testIncidentID = "IW-TIMESTAMP-TEST-001"

    override func setUp() {
        super.setUp()
        service = TimestampAnchorService()
        service.startNewChain(incidentID: testIncidentID)
    }

    override func tearDown() {
        // Clean up persisted files
        cleanupTestFiles()
        service = nil
        super.tearDown()
    }

    private func cleanupTestFiles() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let testDir = appSupport
            .appendingPathComponent("OnTheRecord", isDirectory: true)
            .appendingPathComponent("PendingUploads", isDirectory: true)
            .appendingPathComponent(testIncidentID, isDirectory: true)
        try? FileManager.default.removeItem(at: testDir)
    }

    private func makeChunkHash(_ content: String) -> Data {
        let hash = SHA256.hash(data: Data(content.utf8))
        return Data(hash)
    }

    // MARK: - Chain Creation

    func testStartNewChainResetsState() {
        // Add some anchors first
        _ = service.anchorTimestamp(chunkHash: makeChunkHash("chunk0"), incidentID: testIncidentID, chunkNumber: 0)
        _ = service.anchorTimestamp(chunkHash: makeChunkHash("chunk1"), incidentID: testIncidentID, chunkNumber: 1)

        let beforeReset = service.loadAnchors(incidentID: testIncidentID)
        XCTAssertEqual(beforeReset.count, 2, "Should have 2 anchors before reset")

        // Start a new chain
        service.startNewChain(incidentID: testIncidentID)
        let afterReset = service.loadAnchors(incidentID: testIncidentID)
        XCTAssertEqual(afterReset.count, 0, "Should have 0 anchors after starting new chain")
    }

    func testGenesisAnchorHasNoPreviousHash() {
        let anchor = service.anchorTimestamp(
            chunkHash: makeChunkHash("genesis-chunk"),
            incidentID: testIncidentID,
            chunkNumber: 0
        )

        XCTAssertNil(anchor.previousAnchorHash, "Genesis anchor should have no previous hash")
        XCTAssertFalse(anchor.anchorHash.isEmpty, "Genesis anchor should have its own hash")
        XCTAssertEqual(anchor.chunkNumber, 0)
        XCTAssertEqual(anchor.incidentID, testIncidentID)
    }

    // MARK: - Anchor Insertion with Hash Chaining

    func testAnchorsChainingHashesCorrectly() {
        let anchor0 = service.anchorTimestamp(
            chunkHash: makeChunkHash("chunk-0"),
            incidentID: testIncidentID,
            chunkNumber: 0
        )
        let anchor1 = service.anchorTimestamp(
            chunkHash: makeChunkHash("chunk-1"),
            incidentID: testIncidentID,
            chunkNumber: 1
        )
        let anchor2 = service.anchorTimestamp(
            chunkHash: makeChunkHash("chunk-2"),
            incidentID: testIncidentID,
            chunkNumber: 2
        )

        XCTAssertNil(anchor0.previousAnchorHash, "First anchor has no previous hash")
        XCTAssertEqual(anchor1.previousAnchorHash, anchor0.anchorHash, "Second anchor chains to first")
        XCTAssertEqual(anchor2.previousAnchorHash, anchor1.anchorHash, "Third anchor chains to second")
    }

    func testAnchorContainsChunkHash() {
        let chunkData = "test-chunk-data"
        let expectedHash = SHA256.hash(data: Data(chunkData.utf8))
            .map { String(format: "%02x", $0) }.joined()

        let anchor = service.anchorTimestamp(
            chunkHash: makeChunkHash(chunkData),
            incidentID: testIncidentID,
            chunkNumber: 0
        )

        XCTAssertEqual(anchor.chunkHash, expectedHash, "Anchor should contain the hex-encoded chunk hash")
    }

    func testAnchorContainsTimingInfo() {
        let beforeTime = Date()
        let anchor = service.anchorTimestamp(
            chunkHash: makeChunkHash("timing-test"),
            incidentID: testIncidentID,
            chunkNumber: 0
        )
        let afterTime = Date()

        XCTAssertGreaterThanOrEqual(anchor.wallClockTime, beforeTime, "Wall clock should be >= test start")
        XCTAssertLessThanOrEqual(anchor.wallClockTime, afterTime, "Wall clock should be <= test end")
        XCTAssertGreaterThan(anchor.systemUptime, 0, "System uptime should be positive")
        XCTAssertTrue(anchor.kernelBootTime < Date(), "Kernel boot time should be in the past")
    }

    // MARK: - Chain Integrity Verification

    func testVerifyValidChain() {
        _ = service.anchorTimestamp(chunkHash: makeChunkHash("c0"), incidentID: testIncidentID, chunkNumber: 0)
        _ = service.anchorTimestamp(chunkHash: makeChunkHash("c1"), incidentID: testIncidentID, chunkNumber: 1)
        _ = service.anchorTimestamp(chunkHash: makeChunkHash("c2"), incidentID: testIncidentID, chunkNumber: 2)
        _ = service.anchorTimestamp(chunkHash: makeChunkHash("c3"), incidentID: testIncidentID, chunkNumber: 3)

        let anchors = service.loadAnchors(incidentID: testIncidentID)
        XCTAssertEqual(anchors.count, 4)
        XCTAssertTrue(TimestampAnchorService.verifyChain(anchors), "Valid chain should verify")
    }

    func testVerifyEmptyChainPasses() {
        let valid = TimestampAnchorService.verifyChain([])
        XCTAssertTrue(valid, "Empty chain should be valid")
    }

    func testVerifySingleAnchorChainPasses() {
        let anchor = service.anchorTimestamp(
            chunkHash: makeChunkHash("solo"),
            incidentID: testIncidentID,
            chunkNumber: 0
        )
        let valid = TimestampAnchorService.verifyChain([anchor])
        XCTAssertTrue(valid, "Single anchor chain should be valid")
    }

    // MARK: - Tamper Detection

    func testVerifyDetectsModifiedAnchorHash() {
        _ = service.anchorTimestamp(chunkHash: makeChunkHash("c0"), incidentID: testIncidentID, chunkNumber: 0)
        _ = service.anchorTimestamp(chunkHash: makeChunkHash("c1"), incidentID: testIncidentID, chunkNumber: 1)
        _ = service.anchorTimestamp(chunkHash: makeChunkHash("c2"), incidentID: testIncidentID, chunkNumber: 2)

        var anchors = service.loadAnchors(incidentID: testIncidentID)
        XCTAssertEqual(anchors.count, 3)

        // Tamper with the middle anchor's hash -- create a modified anchor
        let tampered = TimestampAnchorService.TimestampAnchor(
            wallClockTime: anchors[1].wallClockTime,
            systemUptime: anchors[1].systemUptime,
            kernelBootTime: anchors[1].kernelBootTime,
            chunkHash: anchors[1].chunkHash,
            previousAnchorHash: anchors[1].previousAnchorHash,
            anchorHash: "deadbeef00000000deadbeef00000000deadbeef00000000deadbeef00000000",
            incidentID: anchors[1].incidentID,
            chunkNumber: anchors[1].chunkNumber
        )
        anchors[1] = tampered

        XCTAssertFalse(
            TimestampAnchorService.verifyChain(anchors),
            "Chain with tampered anchor hash should fail verification"
        )
    }

    func testVerifyDetectsRemovedAnchor() {
        _ = service.anchorTimestamp(chunkHash: makeChunkHash("c0"), incidentID: testIncidentID, chunkNumber: 0)
        _ = service.anchorTimestamp(chunkHash: makeChunkHash("c1"), incidentID: testIncidentID, chunkNumber: 1)
        _ = service.anchorTimestamp(chunkHash: makeChunkHash("c2"), incidentID: testIncidentID, chunkNumber: 2)

        var anchors = service.loadAnchors(incidentID: testIncidentID)
        // Remove the middle anchor (breaks chain continuity)
        anchors.remove(at: 1)

        XCTAssertFalse(
            TimestampAnchorService.verifyChain(anchors),
            "Chain with removed anchor should fail verification (hash mismatch)"
        )
    }

    func testVerifyDetectsGenesisAnchorWithPreviousHash() {
        // Construct a fake genesis anchor that has a previous hash
        let fakeGenesis = TimestampAnchorService.TimestampAnchor(
            wallClockTime: Date(),
            systemUptime: ProcessInfo.processInfo.systemUptime,
            kernelBootTime: Date().addingTimeInterval(-ProcessInfo.processInfo.systemUptime),
            chunkHash: "abc123",
            previousAnchorHash: "this-should-not-exist-on-genesis",
            anchorHash: "def456",
            incidentID: testIncidentID,
            chunkNumber: 0
        )

        XCTAssertFalse(
            TimestampAnchorService.verifyChain([fakeGenesis]),
            "Genesis anchor with previousAnchorHash should fail verification"
        )
    }

    func testVerifyDetectsUptimeDecreasing() {
        // Construct anchors where uptime goes backwards (clock manipulation)
        let anchor0 = TimestampAnchorService.TimestampAnchor(
            wallClockTime: Date(),
            systemUptime: 1000.0,
            kernelBootTime: Date().addingTimeInterval(-1000.0),
            chunkHash: "hash0",
            previousAnchorHash: nil,
            anchorHash: "ahash0",
            incidentID: testIncidentID,
            chunkNumber: 0
        )
        let anchor1 = TimestampAnchorService.TimestampAnchor(
            wallClockTime: Date(),
            systemUptime: 999.0, // LESS than previous -- tampering!
            kernelBootTime: Date().addingTimeInterval(-999.0),
            chunkHash: "hash1",
            previousAnchorHash: "ahash0",
            anchorHash: "ahash1",
            incidentID: testIncidentID,
            chunkNumber: 1
        )

        XCTAssertFalse(
            TimestampAnchorService.verifyChain([anchor0, anchor1]),
            "Decreasing uptime should fail verification (clock manipulation detected)"
        )
    }

    func testVerifyDetectsEqualUptime() {
        // Equal uptime should also fail (must strictly increase)
        let anchor0 = TimestampAnchorService.TimestampAnchor(
            wallClockTime: Date(),
            systemUptime: 1000.0,
            kernelBootTime: Date().addingTimeInterval(-1000.0),
            chunkHash: "hash0",
            previousAnchorHash: nil,
            anchorHash: "ahash0",
            incidentID: testIncidentID,
            chunkNumber: 0
        )
        let anchor1 = TimestampAnchorService.TimestampAnchor(
            wallClockTime: Date(),
            systemUptime: 1000.0, // EQUAL -- still suspicious
            kernelBootTime: Date().addingTimeInterval(-1000.0),
            chunkHash: "hash1",
            previousAnchorHash: "ahash0",
            anchorHash: "ahash1",
            incidentID: testIncidentID,
            chunkNumber: 1
        )

        XCTAssertFalse(
            TimestampAnchorService.verifyChain([anchor0, anchor1]),
            "Equal uptime should fail verification"
        )
    }

    // MARK: - Disk Persistence (JSONL)

    func testAnchorsPersistToDisk() {
        _ = service.anchorTimestamp(chunkHash: makeChunkHash("persist-0"), incidentID: testIncidentID, chunkNumber: 0)
        _ = service.anchorTimestamp(chunkHash: makeChunkHash("persist-1"), incidentID: testIncidentID, chunkNumber: 1)

        // Verify file exists on disk
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let filePath = appSupport
            .appendingPathComponent("OnTheRecord", isDirectory: true)
            .appendingPathComponent("PendingUploads", isDirectory: true)
            .appendingPathComponent(testIncidentID, isDirectory: true)
            .appendingPathComponent("timestamp_anchors.jsonl")

        XCTAssertTrue(FileManager.default.fileExists(atPath: filePath.path), "JSONL file should exist on disk")

        // Read and verify content
        guard let content = try? String(contentsOf: filePath, encoding: .utf8) else {
            XCTFail("Should be able to read JSONL file")
            return
        }

        let lines = content.split(separator: "\n")
        XCTAssertEqual(lines.count, 2, "File should have 2 lines (one per anchor)")

        // Each line should be valid JSON
        for line in lines {
            let anchor = try? JSONDecoder().decode(
                TimestampAnchorService.TimestampAnchor.self,
                from: Data(line.utf8)
            )
            XCTAssertNotNil(anchor, "Each line should be a valid TimestampAnchor JSON")
        }
    }

    func testLoadAnchorsFromDiskAfterFreshInstance() {
        // Write anchors with the current service
        _ = service.anchorTimestamp(chunkHash: makeChunkHash("disk-0"), incidentID: testIncidentID, chunkNumber: 0)
        _ = service.anchorTimestamp(chunkHash: makeChunkHash("disk-1"), incidentID: testIncidentID, chunkNumber: 1)
        _ = service.anchorTimestamp(chunkHash: makeChunkHash("disk-2"), incidentID: testIncidentID, chunkNumber: 2)

        // Create a fresh service (simulating crash recovery / app restart)
        let freshService = TimestampAnchorService()
        let loaded = freshService.loadAnchors(incidentID: testIncidentID)

        XCTAssertEqual(loaded.count, 3, "Fresh service should recover 3 anchors from disk")
        XCTAssertEqual(loaded[0].chunkNumber, 0)
        XCTAssertEqual(loaded[1].chunkNumber, 1)
        XCTAssertEqual(loaded[2].chunkNumber, 2)

        // Verify the chain is valid
        XCTAssertTrue(TimestampAnchorService.verifyChain(loaded), "Recovered chain should be valid")
    }

    func testLoadAnchorsReturnsEmptyForUnknownIncident() {
        let freshService = TimestampAnchorService()
        let loaded = freshService.loadAnchors(incidentID: "IW-NONEXISTENT-999")
        XCTAssertTrue(loaded.isEmpty, "Unknown incident should return empty array")
    }

    // MARK: - Export

    func testExportAnchorsProducesValidJSON() throws {
        _ = service.anchorTimestamp(chunkHash: makeChunkHash("export-0"), incidentID: testIncidentID, chunkNumber: 0)
        _ = service.anchorTimestamp(chunkHash: makeChunkHash("export-1"), incidentID: testIncidentID, chunkNumber: 1)

        let exportData = try service.exportAnchors(incidentID: testIncidentID)
        XCTAssertFalse(exportData.isEmpty, "Exported data should not be empty")

        // Should be a valid JSON array
        let decoded = try JSONDecoder().decode(
            [TimestampAnchorService.TimestampAnchor].self,
            from: exportData
        )
        XCTAssertEqual(decoded.count, 2, "Should export 2 anchors")
    }

    // MARK: - Anchor Hash Uniqueness

    func testEachAnchorHashIsUnique() {
        var hashes = Set<String>()

        for i in 0..<10 {
            let anchor = service.anchorTimestamp(
                chunkHash: makeChunkHash("unique-\(i)"),
                incidentID: testIncidentID,
                chunkNumber: i
            )
            hashes.insert(anchor.anchorHash)
        }

        XCTAssertEqual(hashes.count, 10, "All 10 anchor hashes should be unique")
    }

    // MARK: - Uptime Monotonicity in Real Chain

    func testRealChainHasMonotonicallyIncreasingUptime() {
        for i in 0..<5 {
            _ = service.anchorTimestamp(
                chunkHash: makeChunkHash("mono-\(i)"),
                incidentID: testIncidentID,
                chunkNumber: i
            )
            // Small delay to ensure uptime advances
            Thread.sleep(forTimeInterval: 0.01)
        }

        let anchors = service.loadAnchors(incidentID: testIncidentID)
        for i in 1..<anchors.count {
            XCTAssertGreaterThan(
                anchors[i].systemUptime,
                anchors[i - 1].systemUptime,
                "System uptime must strictly increase"
            )
        }
    }
}
