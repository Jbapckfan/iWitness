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

    // Receive messages from Watch
    func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        guard let command = message["command"] as? String else {
            replyHandler(["error": "No command"])
            return
        }

        DispatchQueue.main.async {
            switch command {
            case "activate":
                self.onActivateCommand?()
                replyHandler(["status": "activated"])

            case "safe":
                self.onSafeCommand?()
                replyHandler(["status": "safe"])

            case "escalate":
                self.onEscalateCommand?()
                replyHandler(["status": "escalated"])

            case "status":
                // Return current status
                replyHandler([
                    "status": "ok",
                    "timestamp": Date().timeIntervalSince1970
                ])

            default:
                replyHandler(["error": "Unknown command"])
            }
        }
    }
}
