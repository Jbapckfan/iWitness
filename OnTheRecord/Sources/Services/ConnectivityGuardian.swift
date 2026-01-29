import Foundation
import Network
import CoreMotion
import UIKit
import LocalAuthentication

/// Monitors connectivity and detects attempts to disable the phone's network
/// Implements defensive measures against airplane mode, signal jamming, etc.
@MainActor
class ConnectivityGuardian: ObservableObject {
    // MARK: - Published State

    @Published var isConnected: Bool = true
    @Published var connectionType: ConnectionType = .unknown
    @Published var signalLostAt: Date?
    @Published var lastGaspSent: Bool = false
    @Published var isAirplaneModeDetected: Bool = false
    @Published var secondsDisconnected: Int = 0
    @Published var isLowDataMode: Bool = false
    @Published var isExpensive: Bool = false

    enum ConnectionType: String {
        case wifi = "WiFi"
        case cellular = "Cellular"
        case ethernet = "Ethernet"
        case unknown = "Unknown"
        case none = "No Connection"
    }

    // MARK: - Configuration

    struct GuardianConfig {
        var lastGaspDelaySeconds: TimeInterval = 2.0 // Send alert after 2 seconds of no connection
        var escalationDelaySeconds: TimeInterval = 60.0 // Escalate after 60 seconds
        var enableShakeToEscalate: Bool = true
        var shakeThreshold: Double = 2.5 // G-force threshold for shake detection
        var enableAutoLockApp: Bool = true
    }

    var config = GuardianConfig()

    // MARK: - Private State

    private var networkMonitor: NWPathMonitor?
    private var monitorQueue = DispatchQueue(label: "connectivity.monitor")
    private var disconnectTimer: Timer?
    private var lastConnectedTime: Date?
    private var alertService: AlertService?
    private var currentIncidentID: String?

    // Motion manager for shake detection
    private let motionManager = CMMotionManager()
    private var isMonitoringShake = false

    // MARK: - Initialization

    func configure(alertService: AlertService) {
        self.alertService = alertService
    }

    // MARK: - Monitoring Control

    func startMonitoring(incidentID: String) {
        self.currentIncidentID = incidentID
        self.lastGaspSent = false
        self.signalLostAt = nil
        self.secondsDisconnected = 0

        startNetworkMonitoring()

        if config.enableShakeToEscalate {
            startShakeDetection()
        }

        if config.enableAutoLockApp {
            lockAppAndRequirePIN()
        }
    }

    func stopMonitoring() {
        stopNetworkMonitoring()
        stopShakeDetection()
        disconnectTimer?.invalidate()
        disconnectTimer = nil
        currentIncidentID = nil
    }

    // MARK: - Network Monitoring

    private func startNetworkMonitoring() {
        networkMonitor = NWPathMonitor()

        networkMonitor?.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.handleNetworkChange(path)
            }
        }

        networkMonitor?.start(queue: monitorQueue)
    }

    private func stopNetworkMonitoring() {
        networkMonitor?.cancel()
        networkMonitor = nil
    }

    private func handleNetworkChange(_ path: NWPath) {
        let wasConnected = isConnected
        isConnected = path.status == .satisfied

        // Determine connection type
        if path.usesInterfaceType(.wifi) {
            connectionType = .wifi
        } else if path.usesInterfaceType(.cellular) {
            connectionType = .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            connectionType = .ethernet
        } else if path.status == .satisfied {
            connectionType = .unknown
        } else {
            connectionType = .none
        }

        // Check for constraints
        isLowDataMode = path.isConstrained
        isExpensive = path.isExpensive

        // Handle transition to disconnected
        if wasConnected && !isConnected {
            handleDisconnection()
        }

        // Handle reconnection
        if !wasConnected && isConnected {
            handleReconnection()
        }
    }

    private func handleDisconnection() {
        signalLostAt = Date()
        isAirplaneModeDetected = true
        secondsDisconnected = 0

        // Haptic warning
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)

        // Start countdown timer
        disconnectTimer?.invalidate()
        disconnectTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tickDisconnected()
            }
        }

        // Send last gasp after short delay (in case it's just a momentary blip)
        Task {
            try? await Task.sleep(nanoseconds: UInt64(config.lastGaspDelaySeconds * 1_000_000_000))

            if !self.isConnected && !self.lastGaspSent {
                await self.sendLastGaspAlert()
            }
        }
    }

    private func handleReconnection() {
        disconnectTimer?.invalidate()
        disconnectTimer = nil

        let disconnectedDuration = secondsDisconnected
        signalLostAt = nil
        isAirplaneModeDetected = false
        secondsDisconnected = 0

        // Haptic success
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        // Notify UploadService to retry any deferred uploads
        debugLog("[ConnectivityGuardian] Network restored. Triggering deferred upload retry.")
        NotificationCenter.default.post(name: .networkRestored, object: nil)

        // If we were disconnected for a while, send reconnection notice
        if disconnectedDuration > 5, currentIncidentID != nil {
            Task {
                await sendReconnectionAlert(disconnectedSeconds: disconnectedDuration)
            }
        }
    }

    private func tickDisconnected() {
        guard !isConnected else { return }
        secondsDisconnected += 1

        // Escalate after threshold
        if secondsDisconnected >= Int(config.escalationDelaySeconds) {
            Task {
                await escalateForProlongedDisconnection()
            }
        }
    }

    // MARK: - Alert Methods

    private func sendLastGaspAlert() async {
        guard let alertService = alertService,
              let incidentID = currentIncidentID else { return }

        lastGaspSent = true

        // Try to send alert via any available method
        // This might fail if truly offline, but try anyway

        let message = """
        ⚠️ SIGNAL LOST

        Connection lost during incident recording.
        This may indicate phone was placed in airplane mode or signal jammed.

        Incident: \(incidentID)
        Last connected: \(formattedTime(signalLostAt ?? Date()))

        If you don't hear from me, something is wrong.
        """

        // Send via Twilio if configured (might work via cached request)
        if alertService.useTwilio {
            for contact in alertService.contacts {
                do {
                    _ = try await alertService.sendSMSViaTwilio(to: contact.phone, message: message)
                } catch {
                    debugLog("[ConnectivityGuardian] Failed to send emergency SMS to \(contact.phone): \(error.localizedDescription)")
                }
            }
        }
    }

    private func sendReconnectionAlert(disconnectedSeconds: Int) async {
        guard let alertService = alertService else { return }

        let message = """
        ✅ SIGNAL RESTORED

        Connection restored after \(disconnectedSeconds) seconds offline.
        Recording continues.
        """

        if alertService.useTwilio {
            for contact in alertService.contacts.prefix(1) { // Just notify primary contact
                do {
                    _ = try await alertService.sendSMSViaTwilio(to: contact.phone, message: message)
                } catch {
                    debugLog("[ConnectivityGuardian] Failed to send reconnection SMS to \(contact.phone): \(error.localizedDescription)")
                }
            }
        }
    }

    private func escalateForProlongedDisconnection() async {
        guard let alertService = alertService,
              let incidentID = currentIncidentID else { return }

        // This is a serious escalation - phone has been offline for over a minute
        await alertService.escalateAlert(incidentID: incidentID)
    }

    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    // MARK: - Shake Detection

    func startShakeDetection() {
        guard motionManager.isAccelerometerAvailable else { return }
        guard !isMonitoringShake else { return }

        isMonitoringShake = true
        motionManager.accelerometerUpdateInterval = 0.1 // 10 Hz

        motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, error in
            guard let self = self, let data = data else { return }

            let acceleration = sqrt(
                pow(data.acceleration.x, 2) +
                pow(data.acceleration.y, 2) +
                pow(data.acceleration.z, 2)
            )

            // Detect violent shake (subtract 1G for gravity)
            if acceleration > self.config.shakeThreshold {
                self.handleShakeDetected(intensity: acceleration)
            }
        }
    }

    func stopShakeDetection() {
        motionManager.stopAccelerometerUpdates()
        isMonitoringShake = false
    }

    private var lastShakeTime: Date?
    private var shakeCount = 0

    private func handleShakeDetected(intensity: Double) {
        let now = Date()

        // Require 3 shakes within 2 seconds to trigger
        if let lastShake = lastShakeTime, now.timeIntervalSince(lastShake) < 2.0 {
            shakeCount += 1
        } else {
            shakeCount = 1
        }
        lastShakeTime = now

        if shakeCount >= 3 {
            shakeCount = 0
            triggerShakeEscalation()
        }
    }

    private func triggerShakeEscalation() {
        // Heavy haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()

        // Escalate
        guard let incidentID = currentIncidentID else { return }

        Task {
            await alertService?.escalateAlert(incidentID: incidentID)

            // Additional haptic to confirm
            try? await Task.sleep(nanoseconds: 200_000_000)
            let successGenerator = UINotificationFeedbackGenerator()
            successGenerator.notificationOccurred(.success)
        }
    }

    // MARK: - App Lock Protection

    /// Invalidates local biometric cache, requiring PIN to resume.
    /// Note: This only invalidates the app's local LAContext biometric cache.
    /// It does NOT disable system-wide Face ID / Touch ID.
    /// For true biometric disable, the user must press Side + Volume buttons.
    func lockAppAndRequirePIN() {
        let context = LAContext()
        context.invalidate() // Invalidates any cached biometric authentication in this app

        // Track that the lock was engaged
        UserDefaults.standard.set(true, forKey: "appLockEngaged")
    }

    /// Checks if device uses biometric authentication
    var deviceUsesBiometrics: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    /// Returns the type of biometric (Face ID, Touch ID, or none)
    var biometricType: String {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return "None"
        }

        switch context.biometryType {
        case .none:
            return "None"
        case .faceID:
            return "Face ID"
        case .touchID:
            return "Touch ID"
        case .opticID:
            return "Optic ID"
        @unknown default:
            return "Biometric"
        }
    }
}

// MARK: - Secure Phone Helper

extension ConnectivityGuardian {
    /// Instructions for securing phone against forced unlock
    var securePhoneInstructions: [SecureStep] {
        [
            SecureStep(
                number: 1,
                title: "Disable \(biometricType)",
                instruction: "Press and hold Side + Volume buttons for 2 seconds",
                detail: "This shows the power off screen. Press Cancel. \(biometricType) is now disabled until you enter your passcode."
            ),
            SecureStep(
                number: 2,
                title: "Disable Control Center",
                instruction: "Already done if you followed setup",
                detail: "Settings → Face ID & Passcode → Disable 'Control Center' under 'Allow Access When Locked'"
            ),
            SecureStep(
                number: 3,
                title: "Disable Siri",
                instruction: "Prevents voice commands when locked",
                detail: "Settings → Face ID & Passcode → Disable 'Siri' under 'Allow Access When Locked'"
            ),
            SecureStep(
                number: 4,
                title: "Disable USB Accessories",
                instruction: "Prevents data extraction tools",
                detail: "Settings → Face ID & Passcode → Disable 'USB Accessories' (blocks Cellebrite)"
            )
        ]
    }

    struct SecureStep: Identifiable {
        let id = UUID()
        let number: Int
        let title: String
        let instruction: String
        let detail: String
    }
}
