import Foundation
import AVFoundation
import CoreMedia

/// Writes video/audio samples to MP4 chunks
/// Simplified for maximum stability
class ChunkWriter {
    // MARK: - Notifications

    /// Posted when ChunkWriter encounters a critical error that may affect recording integrity.
    /// The `userInfo` dictionary contains "message" (String) describing the failure.
    static let chunkWriteErrorNotification = Notification.Name("com.ontherecord.chunkWriteError")

    private func postWriteError(_ message: String) {
        debugLog("[ChunkWriter] ERROR: \(message)")
        NotificationCenter.default.post(
            name: Self.chunkWriteErrorNotification,
            object: nil,
            userInfo: ["message": message]
        )
    }

    // MARK: - Configuration

    private let incidentID: String
    private let chunkDuration: TimeInterval
    private var quality: AppState.VideoQuality
    private let encryptionService: EncryptionService

    // MARK: - Writer

    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?

    // MARK: - State

    private(set) var currentChunkNumber: Int = 0
    private var sessionStarted = false
    private var isWriting = false
    private let lock = NSLock()

    // MARK: - Retry

    private var setupRetryCount = 0
    private let maxSetupRetries = 3

    // MARK: - Storage
    
    private let outputDirectory: URL
    
    // MARK: - Initialization
    
    init(incidentID: String, chunkDuration: TimeInterval, quality: AppState.VideoQuality, encryptionService: EncryptionService) {
        self.incidentID = incidentID
        self.chunkDuration = chunkDuration
        self.quality = quality
        self.encryptionService = encryptionService
        
        // Use Application Support for persistent storage (excluded from backup)
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupport = paths[0].appendingPathComponent("OnTheRecord/PendingUploads", isDirectory: true)
        self.outputDirectory = appSupport.appendingPathComponent(incidentID, isDirectory: true)
        
        do {
            try FileManager.default.createDirectory(at: self.outputDirectory, withIntermediateDirectories: true)
        } catch {
            debugLog("[ChunkWriter] Failed to create output directory: \(error)")
            NotificationCenter.default.post(
                name: Self.chunkWriteErrorNotification,
                object: nil,
                userInfo: ["message": "Failed to create chunk output directory: \(error.localizedDescription)"]
            )
        }
    }

    // MARK: - Quality Updates

    func updateQuality(_ newQuality: AppState.VideoQuality) {
        lock.lock()
        defer { lock.unlock() }
        self.quality = newQuality
    }



    // MARK: - Chunk Lifecycle

    func startNewChunk() {
        lock.lock()
        defer { lock.unlock() }

        // Only increment chunk number on the first attempt, not on retries
        if setupRetryCount == 0 {
            currentChunkNumber += 1
        }
        sessionStarted = false

        do {
            try setupWriter()
            setupRetryCount = 0
            isWriting = true
        } catch {
            // Clean up the failed writer before retrying
            assetWriter = nil
            videoInput = nil
            audioInput = nil

            if setupRetryCount < maxSetupRetries {
                setupRetryCount += 1
                debugLog("[ChunkWriter] Chunk setup failed, retrying (\(setupRetryCount)/\(maxSetupRetries)): \(error.localizedDescription)")
                // Brief delay then retry (unlock first to avoid deadlock)
                let retryChunk = currentChunkNumber
                lock.unlock()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    guard let self = self else { return }
                    // Re-acquire lock and verify we're still on the same chunk attempt
                    self.lock.lock()
                    guard self.currentChunkNumber == retryChunk, !self.isWriting else {
                        self.lock.unlock()
                        return
                    }
                    self.lock.unlock()
                    self.startNewChunk()
                }
                // We already unlocked; re-lock so the defer unlock is balanced
                lock.lock()
                return
            }
            setupRetryCount = 0
            isWriting = false
            debugLog("[ChunkWriter] CRITICAL: Chunk setup failed after \(maxSetupRetries) retries: \(error.localizedDescription)")
            postWriteError("Failed to setup chunk writer for chunk \(currentChunkNumber) after \(maxSetupRetries) retries: \(error.localizedDescription)")
        }
    }

    /// Finishes writing and returns the URL to the persistent file
    func finalizeCurrentChunk() async -> URL? {
        lock.lock()
        let writer = assetWriter
        let wasWriting = isWriting
        isWriting = false
        sessionStarted = false
        lock.unlock()
        
        guard wasWriting, let writer = writer else { return nil }
        
        // Mark inputs as finished
        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        
        // Async wait for writer to finish (non-blocking)
        await withCheckedContinuation { continuation in
            writer.finishWriting {
                continuation.resume()
            }
        }

        // Verify writer completed successfully
        guard writer.status == .completed else {
            if let error = writer.error {
                postWriteError("Chunk finalization failed: \(error.localizedDescription)")
            } else {
                postWriteError("Chunk finalization finished with unexpected status: \(writer.status.rawValue)")
            }
            return nil
        }

        let outputURL = writer.outputURL

        // clear references
        lock.lock()
        assetWriter = nil
        videoInput = nil
        audioInput = nil
        lock.unlock()

        // Verify file exists and has size
        guard FileManager.default.fileExists(atPath: outputURL.path),
              let attrs = try? FileManager.default.attributesOfItem(atPath: outputURL.path),
              let size = attrs[.size] as? Int64, size > 0 else {
            postWriteError("Finalized chunk file is missing or empty at \(outputURL.lastPathComponent)")
            return nil
        }

        return outputURL
    }

    // MARK: - Sample Appending

    func appendVideoSample(_ sampleBuffer: CMSampleBuffer) {
        lock.lock()
        guard isWriting, let input = videoInput, input.isReadyForMoreMediaData else {
            lock.unlock()
            return
        }

        // Start session on first sample
        if !sessionStarted {
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            assetWriter?.startSession(atSourceTime: timestamp)
            sessionStarted = true
        }

        if !input.append(sampleBuffer) {
            let writerStatus = assetWriter?.status ?? .unknown
            let writerError = assetWriter?.error?.localizedDescription ?? "none"
            lock.unlock()
            postWriteError("Failed to append video sample (writer status: \(writerStatus.rawValue), error: \(writerError))")
            return
        }
        lock.unlock()
    }

    func appendAudioSample(_ sampleBuffer: CMSampleBuffer) {
        lock.lock()
        guard isWriting, sessionStarted, let input = audioInput, input.isReadyForMoreMediaData else {
            lock.unlock()
            return
        }

        if !input.append(sampleBuffer) {
            let writerStatus = assetWriter?.status ?? .unknown
            let writerError = assetWriter?.error?.localizedDescription ?? "none"
            lock.unlock()
            postWriteError("Failed to append audio sample (writer status: \(writerStatus.rawValue), error: \(writerError))")
            return
        }
        lock.unlock()
    }

    // MARK: - Private Helpers

    // MARK: - Private Helpers
    
    private func setupWriter() throws {
        let outputURL = outputDirectory.appendingPathComponent("chunk_\(currentChunkNumber).mp4")
        
        // Remove existing file
        try? FileManager.default.removeItem(at: outputURL)
        
        // Create writer
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true
        
        // Video input
        let videoSettings = videoOutputSettings()
        let vidInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        vidInput.expectsMediaDataInRealTime = true
        if writer.canAdd(vidInput) {
            writer.add(vidInput)
        }
        self.videoInput = vidInput
        
        // Audio input
        let audioSettings = audioOutputSettings()
        let audInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        audInput.expectsMediaDataInRealTime = true
        if writer.canAdd(audInput) {
            writer.add(audInput)
        }
        self.audioInput = audInput
        
        // Start writing
        guard writer.startWriting() else {
            throw NSError(domain: "ChunkWriter", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to start writing"])
        }

        // Set file protection so chunks are accessible while device is locked (for background uploads)
        try? (outputURL as NSURL).setResourceValue(URLFileProtection.completeUnlessOpen, forKey: .fileProtectionKey)

        self.assetWriter = writer
    }
    
    private func videoOutputSettings() -> [String: Any] {
        let resolution = quality.resolution
        
        // Use HEVC (H.265) for ~40% smaller files at same quality
        // Falls back gracefully on older devices
        let codec: AVVideoCodecType = AVAssetExportSession.allExportPresets().contains(AVAssetExportPresetHEVCHighestQuality)
            ? .hevc
            : .h264
        
        var compressionProps: [String: Any] = [
            AVVideoAverageBitRateKey: quality.bitrate,
            AVVideoAllowFrameReorderingKey: false
        ]
        
        // Add profile level based on codec
        if codec == .h264 {
            compressionProps[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel
        }
        
        return [
            AVVideoCodecKey: codec,
            AVVideoWidthKey: resolution.width,
            AVVideoHeightKey: resolution.height,
            AVVideoCompressionPropertiesKey: compressionProps
        ]
    }

    private func audioOutputSettings() -> [String: Any] {
        return [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 2,  // Stereo for better spatial awareness
            AVEncoderBitRateKey: 128000  // 128kbps for stereo
        ]
    }
    
    // MARK: - Cleanup
    
    func cleanup() {
        // We do NOT remove the directory here because UploadService needs the files.
        // Files are cleaned up by UploadService after success.
        // We only clear this instance's reference
    }
    
    // MARK: - Security Hygiene
    
    /// Wipes any orphaned cleartext chunks (.mp4) left behind by a crash
    /// Should be called on app launch
    static func wipeOrphanedChunks() {
        debugLog("[ChunkWriter] Starting orphaned chunk cleanup...")
        guard let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let pendingDir = paths.appendingPathComponent("OnTheRecord/PendingUploads")
        
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(at: pendingDir, includingPropertiesForKeys: nil) else { return }
        
        var wipedCount = 0
        
        for case let fileURL as URL in enumerator {
            // We strictly target .mp4 files which are the cleartext intermediate format
            // We PRESERVE .iwc files which are encrypted and pending upload
            if fileURL.pathExtension == "mp4" {
                do {
                    try fileManager.removeItem(at: fileURL)
                    wipedCount += 1
                    debugLog("[ChunkWriter] Security Wipe: Removed orphaned cleartext chunk at \(fileURL.lastPathComponent)")
                } catch {
                    debugLog("[ChunkWriter] Security Wipe Failed for \(fileURL.lastPathComponent): \(error)")
                }
            }
        }
        
        if wipedCount > 0 {
            debugLog("[ChunkWriter] Security Hygiene: Wiped \(wipedCount) orphaned cleartext chunks.")
        } else {
            debugLog("[ChunkWriter] Security Hygiene: No cleartext orphans found. Clean.")
        }
    }
}
