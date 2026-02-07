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

    // MARK: - Stealth

    @Published var isBlackoutOn: Bool = false

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

    @Published var currentQuality: VideoQuality = {
        if let raw = UserDefaults.standard.string(forKey: "video_quality"),
           let q = VideoQuality(rawValue: raw) {
            return q
        }
        return .high
    }()
    @Published var adaptiveQualityEnabled: Bool = true

    // MARK: - Auto-Stop Timer

    enum MaxRecordingDuration: String, CaseIterable {
        case thirtyMinutes = "30 min"
        case oneHour = "1 hour"
        case twoHours = "2 hours"
        case fourHours = "4 hours"
        case unlimited = "Unlimited"

        var seconds: TimeInterval? {
            switch self {
            case .thirtyMinutes: return 1800
            case .oneHour: return 3600
            case .twoHours: return 7200
            case .fourHours: return 14400
            case .unlimited: return nil
            }
        }

        var warningThreshold: TimeInterval? {
            // Warn 5 minutes before auto-stop
            guard let s = seconds else { return nil }
            return s - 300
        }
    }

    @Published var maxRecordingDuration: MaxRecordingDuration = {
        if let raw = UserDefaults.standard.string(forKey: "max_recording_duration"),
           let val = MaxRecordingDuration(rawValue: raw) {
            return val
        }
        return .oneHour
    }()

    @Published var autoStopWarningShown = false

    // MARK: - Computed Properties

    var isRecording: Bool {
        recordingMode == .recording
    }

    var uploadProgress: Double {
        guard chunksRecorded > 0 else { return 0 }
        return Double(chunksUploaded) / Double(chunksRecorded)
    }

    var formattedDuration: String {
        let totalSeconds = Int(recordingDuration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var estimatedRecordingSizeMB: Double {
        let bytesPerSec = Double(currentQuality.bitrate) / 8.0
        let dualMultiplier: Double = 2.0 // dual camera
        return (recordingDuration * bytesPerSec * dualMultiplier) / (1024 * 1024)
    }

    var autoStopTimeRemaining: TimeInterval? {
        guard let max = maxRecordingDuration.seconds else { return nil }
        let remaining = max - recordingDuration
        return remaining > 0 ? remaining : 0
    }

    var formattedAutoStopRemaining: String? {
        guard autoStopWarningShown, let remaining = autoStopTimeRemaining, remaining > 0 else { return nil }
        let m = Int(remaining) / 60, s = Int(remaining) % 60
        return String(format: "Auto-stop in %d:%02d", m, s)
    }

    var formattedEstimatedSize: String {
        let mb = estimatedRecordingSizeMB
        if mb >= 1024 {
            return String(format: "%.1f GB", mb / 1024)
        }
        return String(format: "%.0f MB", mb)
    }

    /// Color progresses green→orange→red as estimated size grows
    var estimatedSizeColor: (red: Double, green: Double, blue: Double) {
        let mb = estimatedRecordingSizeMB
        if mb < 500 {
            return (0.2, 0.8, 0.3)    // green
        } else if mb < 2048 {
            return (1.0, 0.6, 0.0)    // orange
        } else {
            return (0.9, 0.1, 0.1)    // red
        }
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
            Task { @MainActor in
                guard let self = self, let startTime = self.recordingStartTime else { return }
                self.recordingDuration = Date().timeIntervalSince(startTime)

                // Update Live Activity every 5 seconds
                let elapsed = Int(self.recordingDuration)
                if elapsed % 5 == 0 {
                    LiveActivityManager.shared.update(
                        elapsedSeconds: elapsed,
                        estimatedSizeMB: self.estimatedRecordingSizeMB
                    )
                }

                // Auto-stop warning
                if let warning = self.maxRecordingDuration.warningThreshold,
                   self.recordingDuration >= warning && !self.autoStopWarningShown {
                    self.autoStopWarningShown = true
                    NotificationCenter.default.post(name: .autoStopWarning, object: nil)
                }

                // Auto-stop
                if let max = self.maxRecordingDuration.seconds,
                   self.recordingDuration >= max {
                    NotificationCenter.default.post(name: .autoStopTriggered, object: nil)
                }
            }
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
        isBlackoutOn = false
        autoStopWarningShown = false
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

// MARK: - Auto-Stop Notifications

extension Notification.Name {
    static let autoStopWarning = Notification.Name("com.ontherecord.autoStopWarning")
    static let autoStopTriggered = Notification.Name("com.ontherecord.autoStopTriggered")
}
