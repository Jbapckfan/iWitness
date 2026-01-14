import Foundation
import AVFoundation
import CoreMedia

/// Writes video/audio samples to MP4 chunks
/// Simplified for maximum stability
class ChunkWriter {
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

    private var currentChunkNumber: Int = 0
    private var sessionStarted = false
    private var isWriting = false
    private let lock = NSLock()

    // MARK: - Temp Storage

    private let tempDirectory: URL

    // MARK: - Initialization

    init(incidentID: String, chunkDuration: TimeInterval, quality: AppState.VideoQuality, encryptionService: EncryptionService) {
        self.incidentID = incidentID
        self.chunkDuration = chunkDuration
        self.quality = quality
        self.encryptionService = encryptionService

        // Create temp directory for chunks
        let tempBase = FileManager.default.temporaryDirectory
        self.tempDirectory = tempBase.appendingPathComponent("iWitness/\(incidentID)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
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

        currentChunkNumber += 1
        sessionStarted = false

        do {
            try setupWriter()
            isWriting = true
        } catch {
            print("[iWitness] Failed to setup chunk writer: \(error)")
            isWriting = false
        }
    }

    func finalizeCurrentChunk() -> Data? {
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

        // Wait for writer to finish
        let semaphore = DispatchSemaphore(value: 0)
        writer.finishWriting {
            semaphore.signal()
        }
        semaphore.wait()

        // Read the data
        let outputURL = writer.outputURL
        let data = try? Data(contentsOf: outputURL)

        // Clean up temp file
        try? FileManager.default.removeItem(at: outputURL)

        // Clear references
        lock.lock()
        assetWriter = nil
        videoInput = nil
        audioInput = nil
        lock.unlock()

        return data
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

        input.append(sampleBuffer)
        lock.unlock()
    }

    func appendAudioSample(_ sampleBuffer: CMSampleBuffer) {
        lock.lock()
        guard isWriting, sessionStarted, let input = audioInput, input.isReadyForMoreMediaData else {
            lock.unlock()
            return
        }

        input.append(sampleBuffer)
        lock.unlock()
    }

    // MARK: - Private Helpers

    private func setupWriter() throws {
        let outputURL = tempDirectory.appendingPathComponent("chunk_\(currentChunkNumber).mp4")

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

        self.assetWriter = writer
    }

    private func videoOutputSettings() -> [String: Any] {
        let resolution = quality.resolution
        return [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: resolution.width,
            AVVideoHeightKey: resolution.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: quality.bitrate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoAllowFrameReorderingKey: false
            ]
        ]
    }

    private func audioOutputSettings() -> [String: Any] {
        return [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64000
        ]
    }

    // MARK: - Cleanup

    func cleanup() {
        try? FileManager.default.removeItem(at: tempDirectory)
    }
}
