import Foundation
import WatchConnectivity
import Combine

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

    // MARK: - Commands to iPhone

    /// Tell iPhone to activate iWitness mode
    func sendActivateCommand() {
        guard let session = session, session.isReachable else {
            lastError = "iPhone not reachable"
            return
        }

        let message: [String: Any] = [
            "command": "activate",
            "timestamp": Date().timeIntervalSince1970
        ]

        session.sendMessage(message, replyHandler: { response in
            DispatchQueue.main.async {
                self.lastMessage = response
                if response["status"] as? String == "activated" {
                    self.onRecordingStarted?()
                }
            }
        }, errorHandler: { error in
            DispatchQueue.main.async {
                self.lastError = error.localizedDescription
            }
        })
    }

    /// Tell iPhone to mark as safe
    func sendSafeCommand() {
        guard let session = session, session.isReachable else {
            lastError = "iPhone not reachable"
            return
        }

        let message: [String: Any] = [
            "command": "safe",
            "timestamp": Date().timeIntervalSince1970
        ]

        session.sendMessage(message, replyHandler: { response in
            DispatchQueue.main.async {
                self.lastMessage = response
                if response["status"] as? String == "safe" {
                    self.onRecordingStopped?()
                }
            }
        }, errorHandler: { error in
            DispatchQueue.main.async {
                self.lastError = error.localizedDescription
            }
        })
    }

    /// Tell iPhone to escalate (need help)
    func sendEscalateCommand() {
        guard let session = session, session.isReachable else {
            lastError = "iPhone not reachable"
            return
        }

        let message: [String: Any] = [
            "command": "escalate",
            "timestamp": Date().timeIntervalSince1970
        ]

        session.sendMessage(message, replyHandler: { _ in }, errorHandler: { error in
            DispatchQueue.main.async {
                self.lastError = error.localizedDescription
            }
        })
    }

    /// Request status update from iPhone
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
