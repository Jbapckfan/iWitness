import Foundation
import LocalAuthentication
import SwiftUI

/// Manages app-level biometric/passcode lock
/// Prevents unauthorized access even when phone is unlocked
@MainActor
class AppLockService: ObservableObject {
    static let shared = AppLockService()

    @Published var isLocked: Bool = true
    @Published var isEnabled: Bool
    @Published var authenticationFailed: Bool = false

    init() {
        isEnabled = UserDefaults.standard.object(forKey: "app_lock_enabled") as? Bool ?? false
        isLocked = isEnabled
    }

    var biometricType: LABiometryType {
        let context = LAContext()
        context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return context.biometryType
    }

    var biometricName: String {
        switch biometricType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Passcode"
        }
    }

    func authenticate() {
        guard isEnabled else {
            isLocked = false
            return
        }

        let context = LAContext()
        context.localizedCancelTitle = "Use Passcode"

        var error: NSError?
        let canUseBiometrics = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)

        guard canUseBiometrics else {
            debugLog("[AppLock] Authentication not available: \(error?.localizedDescription ?? "unknown")")
            // Keep locked — do NOT silently bypass when auth is unavailable
            authenticationFailed = true
            return
        }

        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock OnTheRecord to access your recordings and settings") { success, error in
            Task { @MainActor in
                if success {
                    self.isLocked = false
                    self.authenticationFailed = false
                    debugLog("[AppLock] Authentication succeeded")
                } else {
                    self.authenticationFailed = true
                    debugLog("[AppLock] Authentication failed: \(error?.localizedDescription ?? "unknown")")
                }
            }
        }
    }

    func lock() {
        guard isEnabled else { return }
        isLocked = true
        authenticationFailed = false
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "app_lock_enabled")
        if !enabled {
            isLocked = false
        } else {
            isLocked = true
            authenticate()
        }
    }
}
