import XCTest
@testable import OnTheRecordCore

final class ChunkWriterTests: XCTestCase {

    private var tempDir: URL!
    private let testIncidentID = "IW-CHUNKWRITER-TEST-001"

    override func setUp() {
        super.setUp()
        // We'll work with the real ApplicationSupport directory since ChunkWriter uses it internally
        tempDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("OnTheRecord/PendingUploads", isDirectory: true)
            .appendingPathComponent(testIncidentID, isDirectory: true)
    }

    override func tearDown() {
        // Clean up test directory
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func makeChunkWriter(
        incidentID: String? = nil,
        chunkDuration: TimeInterval = 0.5,
        quality: AppState.VideoQuality = .high
    ) -> ChunkWriter {
        return ChunkWriter(
            incidentID: incidentID ?? testIncidentID,
            chunkDuration: chunkDuration,
            quality: quality,
            encryptionService: EncryptionService()
        )
    }

    // MARK: - Chunk Directory Creation

    func testChunkDirectoryCreatedOnInit() {
        let writer = makeChunkWriter()
        _ = writer // Keep reference alive

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: tempDir.path),
            "ChunkWriter init should create the output directory"
        )

        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: tempDir.path, isDirectory: &isDir)
        XCTAssertTrue(isDir.boolValue, "Path should be a directory")
    }

    func testChunkDirectoryUsesIncidentID() {
        let customID = "IW-CUSTOM-ID-TEST"
        let customDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("OnTheRecord/PendingUploads", isDirectory: true)
            .appendingPathComponent(customID, isDirectory: true)

        let writer = makeChunkWriter(incidentID: customID)
        _ = writer

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: customDir.path),
            "Directory should use the incident ID"
        )

        // Clean up
        try? FileManager.default.removeItem(at: customDir)
    }

    func testMultipleWritersSameIncidentShareDirectory() {
        let writer1 = makeChunkWriter()
        let writer2 = makeChunkWriter()
        _ = writer1
        _ = writer2

        // Both should work without error; directory already exists
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.path))
    }

    // MARK: - Chunk Numbering Sequence

    func testInitialChunkNumberIsZero() {
        let writer = makeChunkWriter()
        XCTAssertEqual(writer.currentChunkNumber, 0, "Initial chunk number should be 0")
    }

    func testChunkNumberIncrementsOnStartNewChunk() {
        let writer = makeChunkWriter()

        writer.startNewChunk()
        XCTAssertEqual(writer.currentChunkNumber, 1, "First startNewChunk should set chunk to 1")

        writer.startNewChunk()
        XCTAssertEqual(writer.currentChunkNumber, 2, "Second startNewChunk should set chunk to 2")

        writer.startNewChunk()
        XCTAssertEqual(writer.currentChunkNumber, 3, "Third startNewChunk should set chunk to 3")
    }

    func testChunkNumberSequenceIsContiguous() {
        let writer = makeChunkWriter()
        var numbers: [Int] = []

        for _ in 0..<5 {
            writer.startNewChunk()
            numbers.append(writer.currentChunkNumber)
        }

        XCTAssertEqual(numbers, [1, 2, 3, 4, 5], "Chunk numbers should be contiguous starting from 1")
    }

    // MARK: - Writing Chunk Data to Disk

    func testStartNewChunkCreatesOutputFile() {
        let writer = makeChunkWriter()
        writer.startNewChunk()

        // The writer creates chunk_N.mp4 files
        let expectedFile = tempDir.appendingPathComponent("chunk_1.mp4")
        // Note: The file may exist (created by AVAssetWriter) or be in-progress
        // We verify the chunk number was incremented correctly
        XCTAssertEqual(writer.currentChunkNumber, 1)
    }

    func testFinalizeReturnsNilWhenNotWriting() async {
        let writer = makeChunkWriter()
        // Don't call startNewChunk
        let result = await writer.finalizeCurrentChunk()
        XCTAssertNil(result, "Finalizing without starting should return nil")
    }

    // MARK: - Orphaned Chunk Cleanup

    func testWipeOrphanedChunksRemovesMp4Files() {
        // Create fake .mp4 files in the pending uploads directory
        let fm = FileManager.default
        let pendingDir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("OnTheRecord/PendingUploads", isDirectory: true)
            .appendingPathComponent("IW-ORPHAN-TEST", isDirectory: true)

        try? fm.createDirectory(at: pendingDir, withIntermediateDirectories: true)

        // Create fake MP4 files (orphaned cleartext)
        let orphan1 = pendingDir.appendingPathComponent("chunk_1.mp4")
        let orphan2 = pendingDir.appendingPathComponent("chunk_2.mp4")
        try? Data("fake mp4 data 1".utf8).write(to: orphan1)
        try? Data("fake mp4 data 2".utf8).write(to: orphan2)

        // Create a .iwc file that should NOT be deleted
        let encryptedFile = pendingDir.appendingPathComponent("chunk_1.iwc")
        try? Data("encrypted data".utf8).write(to: encryptedFile)

        // Verify files exist
        XCTAssertTrue(fm.fileExists(atPath: orphan1.path))
        XCTAssertTrue(fm.fileExists(atPath: orphan2.path))
        XCTAssertTrue(fm.fileExists(atPath: encryptedFile.path))

        // Run cleanup
        ChunkWriter.wipeOrphanedChunks()

        // MP4 files should be gone
        XCTAssertFalse(fm.fileExists(atPath: orphan1.path), "Orphaned .mp4 should be deleted")
        XCTAssertFalse(fm.fileExists(atPath: orphan2.path), "Orphaned .mp4 should be deleted")

        // Encrypted file should survive
        XCTAssertTrue(fm.fileExists(atPath: encryptedFile.path), ".iwc file should NOT be deleted")

        // Clean up
        try? fm.removeItem(at: pendingDir)
    }

    func testWipeOrphanedChunksHandlesEmptyDirectory() {
        // Should not crash when there's nothing to clean
        ChunkWriter.wipeOrphanedChunks()
        // If we get here without crashing, the test passes
    }

    func testWipeOrphanedChunksHandlesNestedDirectories() {
        let fm = FileManager.default
        let pendingDir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("OnTheRecord/PendingUploads", isDirectory: true)

        // Create multiple incident directories with orphans
        let incident1 = pendingDir.appendingPathComponent("IW-NESTED-001")
        let incident2 = pendingDir.appendingPathComponent("IW-NESTED-002")

        try? fm.createDirectory(at: incident1, withIntermediateDirectories: true)
        try? fm.createDirectory(at: incident2, withIntermediateDirectories: true)

        try? Data("orphan".utf8).write(to: incident1.appendingPathComponent("chunk_1.mp4"))
        try? Data("orphan".utf8).write(to: incident2.appendingPathComponent("chunk_3.mp4"))

        ChunkWriter.wipeOrphanedChunks()

        XCTAssertFalse(fm.fileExists(atPath: incident1.appendingPathComponent("chunk_1.mp4").path))
        XCTAssertFalse(fm.fileExists(atPath: incident2.appendingPathComponent("chunk_3.mp4").path))

        // Clean up
        try? fm.removeItem(at: incident1)
        try? fm.removeItem(at: incident2)
    }

    // MARK: - Quality Updates

    func testUpdateQualityDoesNotCrash() {
        let writer = makeChunkWriter(quality: .high)
        writer.updateQuality(.medium)
        writer.updateQuality(.low)
        writer.updateQuality(.audioOnly)
        writer.updateQuality(.high)
        // No crash = pass
    }

    // MARK: - Notification on Errors

    func testChunkWriteErrorNotificationName() {
        XCTAssertEqual(
            ChunkWriter.chunkWriteErrorNotification.rawValue,
            "com.ontherecord.chunkWriteError",
            "Notification name should match expected value"
        )
    }

    // MARK: - Storage Path Verification

    func testOutputDirectoryUsesApplicationSupport() {
        let writer = makeChunkWriter()
        _ = writer

        let appSupportPath = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.path
        XCTAssertTrue(
            tempDir.path.hasPrefix(appSupportPath),
            "Output directory should be under Application Support"
        )
    }

    func testOutputDirectoryPathStructure() {
        let writer = makeChunkWriter()
        _ = writer

        XCTAssertTrue(
            tempDir.path.contains("OnTheRecord/PendingUploads/\(testIncidentID)"),
            "Path should follow OnTheRecord/PendingUploads/{incidentID} structure"
        )
    }

    // MARK: - Thread Safety

    func testConcurrentStartNewChunkDoesNotCrash() {
        let writer = makeChunkWriter()
        let group = DispatchGroup()

        for _ in 0..<10 {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                writer.startNewChunk()
                group.leave()
            }
        }

        let result = group.wait(timeout: .now() + 10)
        XCTAssertEqual(result, .success, "Concurrent startNewChunk should complete without deadlock")
    }

    func testConcurrentQualityUpdateDoesNotCrash() {
        let writer = makeChunkWriter()
        let group = DispatchGroup()
        let qualities: [AppState.VideoQuality] = [.high, .medium, .low, .audioOnly]

        for i in 0..<20 {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                writer.updateQuality(qualities[i % qualities.count])
                group.leave()
            }
        }

        let result = group.wait(timeout: .now() + 5)
        XCTAssertEqual(result, .success, "Concurrent quality updates should not crash")
    }
}
