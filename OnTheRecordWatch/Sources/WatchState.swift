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

    // MARK: - Command Delivery Status

    /// Tracks the delivery status of a command sent to the iPhone
    enum CommandStatus: Equatable {
        case idle
        case sending
        case confirmed
        case queued    // Sent via application context (phone not reachable)
        case failed(String)

        static func == (lhs: CommandStatus, rhs: CommandStatus) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.sending, .sending), (.confirmed, .confirmed), (.queued, .queued):
                return true
            case (.failed(let a), .failed(let b)):
                return a == b
            default:
                return false
            }
        }
    }

    @Published var status: RecordingStatus = .idle
    @Published var commandStatus: CommandStatus = .idle
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

    func playWarningHaptic() {
        WKInterfaceDevice.current().play(.retry)
    }

    // MARK: - Command Status Management

    /// Reset command status to idle after a delay
    func resetCommandStatusAfterDelay(_ seconds: TimeInterval = 3.0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self = self else { return }
            // Only reset if still showing a terminal state
            if self.commandStatus == .confirmed || self.commandStatus == .queued {
                self.commandStatus = .idle
            }
            if case .failed = self.commandStatus {
                self.commandStatus = .idle
            }
        }
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
