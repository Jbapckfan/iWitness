import Foundation
import SwiftUI
import Combine

/// Global application state
@MainActor
class AppState: ObservableObject {
    // MARK: - Recording State

    enum RecordingMode {
        case idle
        case recording
        case paused
        case uploading
    }

    @Published var recordingMode: RecordingMode = .idle
    @Published var isICEModeActive: Bool = false

    // MARK: - Session Info

    @Published var currentIncidentID: String?
    @Published var recordingStartTime: Date?
    @Published var recordingDuration: TimeInterval = 0

    private var durationTimer: Timer?

    // MARK: - Upload Status

    @Published var chunksRecorded: Int = 0
    @Published var chunksUploaded: Int = 0
    @Published var uploadQueueDepth: Int = 0
    @Published var currentBitrate: Double = 0

    // MARK: - Alert Status

    @Published var contactsNotified: Int = 0
    @Published var contactsConfirmed: Int = 0

    // MARK: - Location

    @Published var currentLocation: Location?
    @Published var locationHistory: [Location] = []

    // MARK: - Quality Adaptation

    enum VideoQuality: String, CaseIterable {
        case high = "1080p"
        case medium = "720p"
        case low = "480p"
        case audioOnly = "Audio + 1fps"

        var resolution: CGSize {
            switch self {
            case .high: return CGSize(width: 1920, height: 1080)
            case .medium: return CGSize(width: 1280, height: 720)
            case .low: return CGSize(width: 854, height: 480)
            case .audioOnly: return CGSize(width: 426, height: 240)
            }
        }

        var bitrate: Int {
            switch self {
            case .high: return 8_000_000
            case .medium: return 4_000_000
            case .low: return 2_000_000
            case .audioOnly: return 128_000
            }
        }
    }

    @Published var currentQuality: VideoQuality = .high
    @Published var adaptiveQualityEnabled: Bool = true

    // MARK: - Computed Properties

    var isRecording: Bool {
        recordingMode == .recording
    }

    var uploadProgress: Double {
        guard chunksRecorded > 0 else { return 0 }
        return Double(chunksUploaded) / Double(chunksRecorded)
    }

    var formattedDuration: String {
        let minutes = Int(recordingDuration) / 60
        let seconds = Int(recordingDuration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    // MARK: - Actions

    func activateICEMode() {
        isICEModeActive = true
        currentIncidentID = generateIncidentID()
        recordingStartTime = Date()
        recordingDuration = 0
        recordingMode = .recording
        startDurationTimer()
    }

    func deactivateICEMode() {
        stopDurationTimer()
        isICEModeActive = false
        recordingMode = .idle
    }

    private func startDurationTimer() {
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, let startTime = self.recordingStartTime else { return }
            self.recordingDuration = Date().timeIntervalSince(startTime)
        }
    }

    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }

    func markSafe() {
        // Keep incident data but signal safe status
        recordingMode = .uploading
    }

    func reset() {
        stopDurationTimer()
        recordingMode = .idle
        isICEModeActive = false
        currentIncidentID = nil
        recordingStartTime = nil
        recordingDuration = 0
        chunksRecorded = 0
        chunksUploaded = 0
        contactsNotified = 0
        contactsConfirmed = 0
        locationHistory = []
    }

    // MARK: - Private

    private func generateIncidentID() -> String {
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
        let random = String(format: "%04X", arc4random_uniform(65536))
        return "IW-\(timestamp)-\(random)"
    }
}

// MARK: - Location Model

struct Location: Codable, Equatable {
    let latitude: Double
    let longitude: Double
    let accuracy: Double
    let timestamp: Date
    let altitude: Double?
    let speed: Double?

    var coordinate: String {
        String(format: "%.6f, %.6f", latitude, longitude)
    }

    var mapsURL: URL? {
        URL(string: "https://maps.apple.com/?ll=\(latitude),\(longitude)")
    }

    var googleMapsURL: URL? {
        URL(string: "https://www.google.com/maps?q=\(latitude),\(longitude)")
    }
}
