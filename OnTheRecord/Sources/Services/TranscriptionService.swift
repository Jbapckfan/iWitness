import Foundation
import Speech
import AVFoundation
import Combine

/// Real-time on-device speech transcription during recording
/// Uses SFSpeechRecognizer with on-device recognition (iOS 17+, no network needed)
@MainActor
class TranscriptionService: ObservableObject {
    static let shared = TranscriptionService()

    // MARK: - Published State

    @Published var isTranscribing: Bool = false
    @Published var currentTranscript: String = ""
    @Published var segments: [TranscriptSegment] = []
    @Published var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    @Published var error: TranscriptionError?

    // MARK: - Private

    private let speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recordingStartTime: Date?

    // MARK: - Types

    struct TranscriptSegment: Identifiable, Codable {
        let id: UUID
        let text: String
        let startTime: TimeInterval  // seconds from recording start
        let endTime: TimeInterval
        let confidence: Float
        let timestamp: Date

        init(text: String, startTime: TimeInterval, endTime: TimeInterval, confidence: Float) {
            self.id = UUID()
            self.text = text
            self.startTime = startTime
            self.endTime = endTime
            self.confidence = confidence
            self.timestamp = Date()
        }
    }

    enum TranscriptionError: LocalizedError {
        case notAuthorized
        case recognizerUnavailable
        case recognitionFailed(String)

        var errorDescription: String? {
            switch self {
            case .notAuthorized:
                return "Speech recognition not authorized"
            case .recognizerUnavailable:
                return "Speech recognizer not available"
            case .recognitionFailed(let reason):
                return "Recognition failed: \(reason)"
            }
        }
    }

    // MARK: - Initialization

    init() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
    }

    // MARK: - Authorization

    func requestAuthorization() async -> Bool {
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                Task { @MainActor in
                    self.authorizationStatus = status
                    continuation.resume(returning: status == .authorized)
                }
            }
        }
    }

    // MARK: - Transcription Control

    /// Start transcription from an audio engine tap
    func startTranscription(audioEngine: AVAudioEngine) throws {
        guard authorizationStatus == .authorized else {
            throw TranscriptionError.notAuthorized
        }

        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            throw TranscriptionError.recognizerUnavailable
        }

        // Cancel any existing task
        stopTranscription()

        recordingStartTime = Date()
        segments = []
        currentTranscript = ""

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true

        // Prefer on-device recognition (iOS 13+, much better on iOS 17+)
        if #available(iOS 13, *) {
            request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        }

        // Add speech context hints for evidence-related vocabulary
        request.contextualStrings = [
            "officer", "badge number", "license plate",
            "I do not consent", "I'm recording", "witness",
            "hands up", "stop", "help", "emergency"
        ]

        self.recognitionRequest = request

        // Install audio tap
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        // Start recognition
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self = self else { return }

                if let result = result {
                    self.currentTranscript = result.bestTranscription.formattedString

                    // Extract segments with timestamps
                    self.updateSegments(from: result.bestTranscription)

                    if result.isFinal {
                        self.isTranscribing = false
                    }
                }

                if let error = error {
                    debugLog("[TranscriptionService] Recognition error: \(error)")
                    self.error = .recognitionFailed(error.localizedDescription)
                }
            }
        }

        isTranscribing = true
    }

    /// Feed audio samples directly (alternative to engine tap)
    func appendAudioSample(_ sampleBuffer: CMSampleBuffer) {
        guard let request = recognitionRequest else { return }

        // Convert CMSampleBuffer to AVAudioPCMBuffer
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let audioStreamBasicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            return
        }

        guard let format = AVAudioFormat(streamDescription: audioStreamBasicDescription) else {
            return
        }

        let numSamples = CMSampleBufferGetNumSamples(sampleBuffer)
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(numSamples)) else {
            return
        }
        pcmBuffer.frameLength = AVAudioFrameCount(numSamples)

        if let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) {
            var length: Int = 0
            var dataPointer: UnsafeMutablePointer<Int8>?
            CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)

            if let source = dataPointer, let destination = pcmBuffer.int16ChannelData?[0] {
                memcpy(destination, source, min(length, Int(pcmBuffer.frameCapacity) * MemoryLayout<Int16>.size))
            }
        }

        request.append(pcmBuffer)
    }

    func stopTranscription() {
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isTranscribing = false
    }

    // MARK: - Segment Processing

    private func updateSegments(from transcription: SFTranscription) {
        guard let startTime = recordingStartTime else { return }
        let elapsed = Date().timeIntervalSince(startTime)

        var newSegments: [TranscriptSegment] = []

        for segment in transcription.segments {
            let seg = TranscriptSegment(
                text: segment.substring,
                startTime: segment.timestamp,
                endTime: segment.timestamp + segment.duration,
                confidence: segment.confidence
            )
            newSegments.append(seg)
        }

        segments = newSegments
    }

    // MARK: - Export

    /// Export transcript as SRT subtitle format
    func exportAsSRT() -> String {
        var srt = ""
        for (index, segment) in segments.enumerated() {
            srt += "\(index + 1)\n"
            srt += "\(formatSRTTime(segment.startTime)) --> \(formatSRTTime(segment.endTime))\n"
            srt += "\(segment.text)\n\n"
        }
        return srt
    }

    /// Export transcript as VTT subtitle format
    func exportAsVTT() -> String {
        var vtt = "WEBVTT\n\n"
        for (index, segment) in segments.enumerated() {
            vtt += "\(index + 1)\n"
            vtt += "\(formatVTTTime(segment.startTime)) --> \(formatVTTTime(segment.endTime))\n"
            vtt += "\(segment.text)\n\n"
        }
        return vtt
    }

    /// Export as plain text with timestamps
    func exportAsText() -> String {
        var text = "OnTheRecord Transcript\n"
        text += "======================\n\n"

        for segment in segments {
            let time = formatTimestamp(segment.startTime)
            text += "[\(time)] \(segment.text)\n"
        }

        return text
    }

    /// Save transcript to file
    func saveTranscript(incidentID: String) throws -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("OnTheRecord/Transcripts", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Save SRT
        let srtURL = dir.appendingPathComponent("\(incidentID).srt")
        try exportAsSRT().write(to: srtURL, atomically: true, encoding: .utf8)

        // Save plain text
        let txtURL = dir.appendingPathComponent("\(incidentID).txt")
        try exportAsText().write(to: txtURL, atomically: true, encoding: .utf8)

        // Save segments as JSON for later processing
        let jsonURL = dir.appendingPathComponent("\(incidentID)_segments.json")
        let data = try JSONEncoder().encode(segments)
        try data.write(to: jsonURL)

        return srtURL
    }

    // MARK: - Time Formatting

    private func formatSRTTime(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        let millis = Int((seconds.truncatingRemainder(dividingBy: 1)) * 1000)
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, secs, millis)
    }

    private func formatVTTTime(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        let millis = Int((seconds.truncatingRemainder(dividingBy: 1)) * 1000)
        return String(format: "%02d:%02d:%02d.%03d", hours, minutes, secs, millis)
    }

    private func formatTimestamp(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
}
