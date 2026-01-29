import Foundation
import WatchConnectivity
import Combine

/// Logs messages only in DEBUG builds to prevent sensitive data leakage in production
/// - Parameter message: The message to log
func debugLog(_ message: String) {
    #if DEBUG
    print(message)
    #endif
}

/// Manages communication between Watch and iPhone
class WatchConnectivityManager: NSObject, ObservableObject {
    // MARK: - Published State

    @Published var isReachable: Bool = false
    @Published var isActivated: Bool = false
    @Published var lastMessage: [String: Any]?
    @Published var lastError: String?

    // MARK: - Callbacks

    var onRecordingStarted: (() -> Void)?
    var onRecordingStopped: (() -> Void)?
    var onStatusUpdate: (([String: Any]) -> Void)?

    // MARK: - Session

    private var session: WCSession?

    // MARK: - Initialization

    override init() {
        super.init()
    }

    // MARK: - Activation

    func activate() {
        guard WCSession.isSupported() else {
            lastError = "WatchConnectivity not supported"
            return
        }

        session = WCSession.default
        session?.delegate = self
        session?.activate()
    }

    // MARK: - Command Delivery Callback

    /// Called when a command delivery result is determined (confirmed, queued, or failed)
    var onCommandResult: ((Bool, Bool) -> Void)?  // (confirmed: Bool, queued: Bool)

    // MARK: - Commands to iPhone

    /// Tell iPhone to activate OnTheRecord mode
    func sendActivateCommand() {
        let message: [String: Any] = [
            "command": "activate",
            "timestamp": Date().timeIntervalSince1970
        ]

        sendCommandWithConfirmation(message) { [weak self] confirmed in
            DispatchQueue.main.async {
                if confirmed {
                    self?.onRecordingStarted?()
                }
            }
        }
    }

    /// Tell iPhone to mark as safe
    func sendSafeCommand() {
        let message: [String: Any] = [
            "command": "safe",
            "timestamp": Date().timeIntervalSince1970
        ]

        sendCommandWithConfirmation(message) { [weak self] confirmed in
            DispatchQueue.main.async {
                if confirmed {
                    self?.onRecordingStopped?()
                }
            }
        }
    }

    /// Tell iPhone to escalate (need help)
    func sendEscalateCommand() {
        let message: [String: Any] = [
            "command": "escalate",
            "timestamp": Date().timeIntervalSince1970
        ]

        sendCommandWithConfirmation(message) { _ in
            // Escalation sent — UI feedback handled by commandStatus
        }
    }

    /// Request status update from iPhone (best-effort, no confirmation needed)
    func requestStatus() {
        guard let session = session, session.isReachable else { return }

        let message: [String: Any] = [
            "command": "status"
        ]

        session.sendMessage(message, replyHandler: { response in
            DispatchQueue.main.async {
                self.onStatusUpdate?(response)
            }
        }, errorHandler: { _ in })
    }

    // MARK: - Command Delivery with Confirmation

    /// Sends a command to the iPhone with delivery acknowledgment.
    /// If the phone is unreachable, falls back to application context (queued delivery).
    /// - Parameters:
    ///   - command: The command dictionary to send
    ///   - completion: Called with `true` if the phone acknowledged, `false` otherwise
    private func sendCommandWithConfirmation(_ command: [String: Any], completion: @escaping (Bool) -> Void) {
        guard let session = session, session.isReachable else {
            debugLog("[WatchConnectivity] Phone not reachable, attempting context transfer")
            lastError = "iPhone not reachable"

            // Fallback to application context (queued, delivered when phone is available)
            do {
                try session?.updateApplicationContext(command)
                debugLog("[WatchConnectivity] Command queued via application context")
                DispatchQueue.main.async {
                    self.onCommandResult?(false, true) // Not confirmed, but queued
                }
                completion(false)
            } catch {
                debugLog("[WatchConnectivity] Failed to queue command: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.lastError = error.localizedDescription
                    self.onCommandResult?(false, false) // Not confirmed, not queued
                }
                completion(false)
            }
            return
        }

        session.sendMessage(command, replyHandler: { reply in
            let acknowledged = reply["acknowledged"] as? Bool ?? false
            debugLog("[WatchConnectivity] Phone reply: acknowledged=\(acknowledged)")
            DispatchQueue.main.async {
                self.lastMessage = reply
                if acknowledged {
                    self.onCommandResult?(true, false) // Confirmed
                } else {
                    self.onCommandResult?(false, false) // Reply received but not acknowledged
                }
            }
            completion(acknowledged)
        }, errorHandler: { error in
            debugLog("[WatchConnectivity] Command delivery failed: \(error.localizedDescription)")

            // Fallback: try application context
            var queued = false
            do {
                try self.session?.updateApplicationContext(command)
                queued = true
                debugLog("[WatchConnectivity] Command queued via application context after send failure")
            } catch {
                debugLog("[WatchConnectivity] Failed to queue fallback command: \(error.localizedDescription)")
            }

            DispatchQueue.main.async {
                self.lastError = error.localizedDescription
                self.onCommandResult?(false, queued)
            }
            completion(false)
        })
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.isActivated = activationState == .activated
            self.isReachable = session.isReachable

            if let error = error {
                self.lastError = error.localizedDescription
            }
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
        }
    }

    // Receive messages from iPhone
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        DispatchQueue.main.async {
            self.handleIncomingMessage(message)
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        DispatchQueue.main.async {
            self.handleIncomingMessage(message)
            replyHandler(["received": true])
        }
    }

    private func handleIncomingMessage(_ message: [String: Any]) {
        lastMessage = message

        if let status = message["recordingStatus"] as? String {
            if status == "started" {
                onRecordingStarted?()
            } else if status == "stopped" {
                onRecordingStopped?()
            }
        }

        if let _ = message["statusUpdate"] as? Bool {
            onStatusUpdate?(message)
        }
    }

    // Receive application context (background sync)
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        DispatchQueue.main.async {
            self.onStatusUpdate?(applicationContext)
        }
    }
}
