import Foundation
import WatchConnectivity
import Combine

/// Manages communication from iPhone to Apple Watch
class PhoneConnectivityManager: NSObject, ObservableObject {
    // MARK: - Singleton

    static let shared = PhoneConnectivityManager()

    // MARK: - Published State

    @Published var isWatchReachable: Bool = false
    @Published var isWatchPaired: Bool = false
    @Published var isWatchAppInstalled: Bool = false

    // MARK: - Callbacks

    var onActivateCommand: (() -> Void)?
    var onSafeCommand: (() -> Void)?
    var onEscalateCommand: (() -> Void)?

    // MARK: - Session

    private var session: WCSession?

    // MARK: - Initialization

    override init() {
        super.init()
    }

    // MARK: - Activation

    func activate() {
        guard WCSession.isSupported() else { return }

        session = WCSession.default
        session?.delegate = self
        session?.activate()
    }

    // MARK: - Send Updates to Watch

    /// Send recording status update to Watch
    func sendRecordingStarted() {
        sendMessage([
            "recordingStatus": "started",
            "timestamp": Date().timeIntervalSince1970
        ])
    }

    func sendRecordingStopped() {
        sendMessage([
            "recordingStatus": "stopped",
            "timestamp": Date().timeIntervalSince1970
        ])
    }

    /// Send status update to Watch
    func sendStatusUpdate(chunksUploaded: Int, contactsNotified: Int, duration: TimeInterval) {
        let context: [String: Any] = [
            "statusUpdate": true,
            "chunksUploaded": chunksUploaded,
            "contactsNotified": contactsNotified,
            "duration": duration,
            "timestamp": Date().timeIntervalSince1970
        ]

        // Use application context for background updates
        try? session?.updateApplicationContext(context)

        // Also send as message if reachable
        if session?.isReachable == true {
            sendMessage(context)
        }
    }

    // MARK: - Command Confirmation

    /// Send a command to the Watch with delivery confirmation.
    /// Falls back to application context if the Watch is not reachable.
    func sendCommandWithConfirmation(_ command: [String: Any], completion: @escaping (Bool) -> Void) {
        guard let session = session, session.isReachable else {
            debugLog("[PhoneConnectivity] Watch not reachable, attempting context transfer")
            // Fallback to application context (queued, delivered later)
            do {
                try session?.updateApplicationContext(command)
                debugLog("[PhoneConnectivity] Command queued via application context")
                completion(false) // Queued but not confirmed
            } catch {
                debugLog("[PhoneConnectivity] Failed to queue command: \(error.localizedDescription)")
                completion(false)
            }
            return
        }

        session.sendMessage(command, replyHandler: { reply in
            if let ack = reply["acknowledged"] as? Bool, ack {
                debugLog("[PhoneConnectivity] Command acknowledged by Watch")
                completion(true)
            } else {
                debugLog("[PhoneConnectivity] Watch replied but did not acknowledge")
                completion(false)
            }
        }, errorHandler: { error in
            debugLog("[PhoneConnectivity] Command delivery failed: \(error.localizedDescription)")
            // Fallback: try application context
            do {
                try self.session?.updateApplicationContext(command)
                debugLog("[PhoneConnectivity] Command queued via application context after send failure")
            } catch {
                debugLog("[PhoneConnectivity] Failed to queue fallback command: \(error.localizedDescription)")
            }
            completion(false)
        })
    }

    // MARK: - Private

    private func sendMessage(_ message: [String: Any]) {
        guard let session = session, session.isReachable else { return }

        session.sendMessage(message, replyHandler: nil, errorHandler: { error in
            debugLog("[OnTheRecord] Watch send error: \(error)")
        })
    }
}

// MARK: - WCSessionDelegate

extension PhoneConnectivityManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.isWatchPaired = session.isPaired
            self.isWatchAppInstalled = session.isWatchAppInstalled
            self.isWatchReachable = session.isReachable
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {
        // Handle session becoming inactive
    }

    func sessionDidDeactivate(_ session: WCSession) {
        // Reactivate session
        session.activate()
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isWatchReachable = session.isReachable
        }
    }

    // MARK: - Receive Messages from Watch

    /// Receive message from Watch (no reply expected) — fallback path
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        debugLog("[PhoneConnectivity] Received message from Watch (no reply): \(message)")
        DispatchQueue.main.async {
            self.handleReceivedMessage(message)
        }
    }

    /// Receive message from Watch with reply handler — primary path with acknowledgment
    func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        debugLog("[PhoneConnectivity] Received message from Watch with reply handler: \(message)")

        DispatchQueue.main.async {
            let result = self.handleReceivedMessage(message)
            var reply: [String: Any] = [
                "acknowledged": true,
                "timestamp": Date().timeIntervalSince1970
            ]
            // Merge command-specific result into reply
            for (key, value) in result {
                reply[key] = value
            }
            replyHandler(reply)
        }
    }

    // MARK: - Message Handling

    /// Processes an incoming command message from the Watch.
    /// Returns a dictionary of command-specific result fields.
    @discardableResult
    private func handleReceivedMessage(_ message: [String: Any]) -> [String: Any] {
        guard let command = message["command"] as? String else {
            debugLog("[PhoneConnectivity] Received message with no command key")
            return ["error": "No command"]
        }

        switch command {
        case "activate":
            debugLog("[PhoneConnectivity] Processing activate command")
            onActivateCommand?()
            return ["status": "activated"]

        case "safe":
            debugLog("[PhoneConnectivity] Processing safe command")
            onSafeCommand?()
            return ["status": "safe"]

        case "escalate":
            debugLog("[PhoneConnectivity] Processing escalate command")
            onEscalateCommand?()
            return ["status": "escalated"]

        case "status":
            debugLog("[PhoneConnectivity] Processing status request")
            return [
                "status": "ok",
                "timestamp": Date().timeIntervalSince1970
            ]

        default:
            debugLog("[PhoneConnectivity] Unknown command: \(command)")
            return ["error": "Unknown command"]
        }
    }
}
