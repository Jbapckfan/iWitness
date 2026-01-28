import Foundation
import SwiftUI
import Combine
import WatchKit

/// Manages state for the Apple Watch app
@MainActor
class WatchState: ObservableObject {
    // MARK: - Recording State

    enum RecordingStatus: String {
        case idle = "Ready"
        case activating = "Activating..."
        case recording = "Recording"
        case uploading = "Uploading"
        case safe = "Safe"
        case error = "Error"
    }

    @Published var status: RecordingStatus = .idle
    @Published var isConnectedToPhone: Bool = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var chunksUploaded: Int = 0
    @Published var contactsNotified: Int = 0
    @Published var lastError: String?

    // MARK: - Haptic Feedback

    func playActivationHaptic() {
        WKInterfaceDevice.current().play(.start)
    }

    func playSuccessHaptic() {
        WKInterfaceDevice.current().play(.success)
    }

    func playErrorHaptic() {
        WKInterfaceDevice.current().play(.failure)
    }

    func playUrgentHaptic() {
        WKInterfaceDevice.current().play(.directionUp)
    }

    // MARK: - Timer

    private var durationTimer: Timer?

    func startDurationTimer() {
        recordingDuration = 0
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.recordingDuration += 1
            }
        }
    }

    func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }

    // MARK: - Formatted Duration

    var formattedDuration: String {
        let minutes = Int(recordingDuration) / 60
        let seconds = Int(recordingDuration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
