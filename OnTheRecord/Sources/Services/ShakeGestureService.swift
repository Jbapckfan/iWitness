import Foundation
import CoreMotion
import UIKit
import Combine

/// Service responsible for detecting significant shake gestures to trigger emergency actions
/// such as "Superlock" (locking the screen/stopping recording) or starting a recording panic mode.
/// Uses CoreMotion for reliable detection independent of the responder chain.
final class ShakeGestureService: ObservableObject {
    static let shared = ShakeGestureService()
    
    // Configurable sensitivity
    private let shakeThreshold: Double = 2.5 // G-force threshold
    private let shakeInterval: TimeInterval = 0.5 // Minimum time between shakes
    
    private let motionManager = CMMotionManager()
    private var lastShakeTime: Date = .distantPast
    
    // Publishers for events
    let onShakeDetected = PassthroughSubject<Void, Never>()
    
    @Published var isMonitoring = false
    
    private init() {}
    
    /// Haptic feedback generator for confirmation
    private let feedbackGenerator = UINotificationFeedbackGenerator()
    
    /// Starts monitoring for shake gestures
    func startMonitoring() {
        guard !isMonitoring else { return }
        guard motionManager.isAccelerometerAvailable else {
            debugLog("[ShakeGestureService] Accelerometer not available")
            return
        }
        
        motionManager.accelerometerUpdateInterval = 0.1
        motionManager.startAccelerometerUpdates(to: .main) { [weak self] (data, error) in
            guard let self = self, let data = data else { return }
            self.detectShake(acceleration: data.acceleration)
        }
        
        isMonitoring = true
        debugLog("[ShakeGestureService] Started monitoring")
    }
    
    /// Stops monitoring
    func stopMonitoring() {
        guard isMonitoring else { return }
        motionManager.stopAccelerometerUpdates()
        isMonitoring = false
        debugLog("[ShakeGestureService] Stopped monitoring")
    }
    
    private func detectShake(acceleration: CMAcceleration) {
        // Calculate total G-force
        let gForce = sqrt(pow(acceleration.x, 2) + pow(acceleration.y, 2) + pow(acceleration.z, 2))
        
        if gForce > shakeThreshold {
            let now = Date()
            if now.timeIntervalSince(lastShakeTime) > shakeInterval {
                debugLog("[ShakeGestureService] Shake detected! G-Force: \(gForce)")
                lastShakeTime = now
                
                // Trigger action on main thread
                DispatchQueue.main.async {
                    self.triggerShakeAction()
                }
            }
        }
    }
    
    private func triggerShakeAction() {
        // Haptic confirmation
        feedbackGenerator.notificationOccurred(.warning)
        
        // Notify subscribers
        onShakeDetected.send()
        
        // FUTURE: If we want direct actions here, we can add them.
        // For now, we broadcast the event for RecordingService or AppState to handle.
        // Common use case: "Superlock" - obscure screen, keep recording, require PIN to unlock.
    }
}
