import Foundation
import AVFoundation

/// Real-time audio enhancement for clearer evidence recordings
/// Applies speech-frequency bandpass filtering and noise reduction
class AudioEnhancementService {
    static let shared = AudioEnhancementService()

    // MARK: - Configuration

    struct EnhancementConfig {
        var isEnabled: Bool = false
        var speechBoostEnabled: Bool = true      // Boost 300Hz-3400Hz
        var windNoiseReduction: Bool = true       // Suppress below 200Hz
        var gainBoostDB: Float = 6.0              // Additional gain in dB
    }

    var config = EnhancementConfig()

    // MARK: - Audio Processing

    private var audioEngine: AVAudioEngine?
    private var eqNode: AVAudioUnitEQ?

    /// Configure the audio engine with enhancement EQ
    func configureEnhancement(on engine: AVAudioEngine) -> AVAudioUnitEQ? {
        guard config.isEnabled else { return nil }

        let eq = AVAudioUnitEQ(numberOfBands: 4)

        // Band 0: High-pass filter to cut wind noise (below 200Hz)
        if config.windNoiseReduction {
            let band0 = eq.bands[0]
            band0.filterType = .highPass
            band0.frequency = 200
            band0.bandwidth = 1.0
            band0.gain = 0
            band0.bypass = false
        }

        // Band 1: Low-mid boost for male voice clarity (300-800Hz)
        if config.speechBoostEnabled {
            let band1 = eq.bands[1]
            band1.filterType = .parametric
            band1.frequency = 500
            band1.bandwidth = 1.5
            band1.gain = config.gainBoostDB * 0.5
            band1.bypass = false
        }

        // Band 2: Mid boost for speech intelligibility (1000-3000Hz)
        if config.speechBoostEnabled {
            let band2 = eq.bands[2]
            band2.filterType = .parametric
            band2.frequency = 2000
            band2.bandwidth = 2.0
            band2.gain = config.gainBoostDB
            band2.bypass = false
        }

        // Band 3: Low-pass to reduce high-frequency hiss (above 8kHz)
        let band3 = eq.bands[3]
        band3.filterType = .lowPass
        band3.frequency = 8000
        band3.bandwidth = 1.0
        band3.gain = 0
        band3.bypass = false

        self.eqNode = eq
        return eq
    }

    /// Process an audio buffer with enhancement (offline processing)
    func enhanceAudioFile(inputURL: URL, outputURL: URL) async throws {
        let inputFile = try AVAudioFile(forReading: inputURL)
        let format = inputFile.processingFormat

        let engine = AVAudioEngine()
        let playerNode = AVAudioPlayerNode()

        engine.attach(playerNode)

        if let eq = configureEnhancement(on: engine) {
            engine.attach(eq)
            engine.connect(playerNode, to: eq, format: format)
            engine.connect(eq, to: engine.mainMixerNode, format: format)
        } else {
            engine.connect(playerNode, to: engine.mainMixerNode, format: format)
        }

        // Write enhanced audio to output file
        let outputFile = try AVAudioFile(forWriting: outputURL, settings: inputFile.fileFormat.settings)

        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            try? outputFile.write(from: buffer)
        }

        try engine.start()
        playerNode.scheduleFile(inputFile, at: nil, completionHandler: nil)
        playerNode.play()

        // Wait for playback to complete
        let duration = Double(inputFile.length) / inputFile.processingFormat.sampleRate
        try await Task.sleep(nanoseconds: .seconds(duration) + .milliseconds(500))

        engine.mainMixerNode.removeTap(onBus: 0)
        engine.stop()
    }

    // MARK: - Settings Persistence

    func loadSettings() {
        config.isEnabled = UserDefaults.standard.bool(forKey: "audio_enhancement_enabled")
        config.speechBoostEnabled = UserDefaults.standard.object(forKey: "audio_speech_boost") as? Bool ?? true
        config.windNoiseReduction = UserDefaults.standard.object(forKey: "audio_wind_reduction") as? Bool ?? true
        config.gainBoostDB = UserDefaults.standard.object(forKey: "audio_gain_db") as? Float ?? 6.0
    }

    func saveSettings() {
        UserDefaults.standard.set(config.isEnabled, forKey: "audio_enhancement_enabled")
        UserDefaults.standard.set(config.speechBoostEnabled, forKey: "audio_speech_boost")
        UserDefaults.standard.set(config.windNoiseReduction, forKey: "audio_wind_reduction")
        UserDefaults.standard.set(config.gainBoostDB, forKey: "audio_gain_db")
    }
}
