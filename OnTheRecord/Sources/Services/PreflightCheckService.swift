import Foundation
import AVFoundation
import Contacts
import CoreLocation

/// Runs pre-recording checks to ensure the app is ready for an incident.
/// Hard failures (camera/mic denied) block recording. Warnings are logged but don't block.
@MainActor
class PreflightCheckService: ObservableObject {
    // MARK: - Report

    struct PreflightReport {
        let checks: [CheckResult]

        var hasBlockers: Bool {
            checks.contains { $0.severity == .blocker }
        }

        var warnings: [CheckResult] {
            checks.filter { $0.severity == .warning }
        }

        var blockers: [CheckResult] {
            checks.filter { $0.severity == .blocker }
        }
    }

    struct CheckResult {
        let name: String
        let passed: Bool
        let severity: Severity
        let message: String

        enum Severity {
            case blocker
            case warning
        }
    }

    // MARK: - Public API

    @Published var lastReport: PreflightReport?

    func runChecks(
        alertService: AlertService,
        uploadService: UploadService
    ) async -> PreflightReport {
        var results: [CheckResult] = []

        // 1. Camera permission (blocker)
        let cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        results.append(CheckResult(
            name: "Camera",
            passed: cameraStatus == .authorized,
            severity: .blocker,
            message: cameraStatus == .authorized
                ? "Camera access granted"
                : "Camera access denied — recording cannot start"
        ))

        // 2. Microphone permission (blocker)
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        results.append(CheckResult(
            name: "Microphone",
            passed: micStatus == .authorized,
            severity: .blocker,
            message: micStatus == .authorized
                ? "Microphone access granted"
                : "Microphone access denied — recording cannot start"
        ))

        // 3. Emergency contacts configured (warning)
        let hasContacts = !alertService.contacts.isEmpty
        results.append(CheckResult(
            name: "Contacts",
            passed: hasContacts,
            severity: .warning,
            message: hasContacts
                ? "\(alertService.contacts.count) emergency contact(s) configured"
                : "No emergency contacts — alerts will not be sent"
        ))

        // 4. Twilio configured (warning)
        let hasTwilio = alertService.useTwilio
        results.append(CheckResult(
            name: "Twilio SMS",
            passed: hasTwilio,
            severity: .warning,
            message: hasTwilio
                ? "Twilio SMS configured"
                : "Twilio not configured — SMS alerts disabled"
        ))

        // 5. Upload destination configured (blocker — without offsite backup, evidence stays on-device)
        let hasDestinations = !uploadService.destinations.isEmpty
        results.append(CheckResult(
            name: "Upload",
            passed: hasDestinations,
            severity: .blocker,
            message: hasDestinations
                ? "\(uploadService.destinations.count) upload destination(s) configured"
                : "No upload destinations — if your phone is seized, your evidence is gone"
        ))

        // 6. Location permission (warning)
        let locationAuthorized = CLLocationManager.authorizationStatus() == .authorizedWhenInUse
            || CLLocationManager.authorizationStatus() == .authorizedAlways
        results.append(CheckResult(
            name: "Location",
            passed: locationAuthorized,
            severity: .warning,
            message: locationAuthorized
                ? "Location access granted"
                : "Location unavailable — chunks will lack GPS metadata"
        ))

        let report = PreflightReport(checks: results)
        lastReport = report

        // Log summary
        for check in results where !check.passed {
            let level = check.severity == .blocker ? "BLOCKER" : "WARNING"
            debugLog("[Preflight] \(level): \(check.message)")
        }

        return report
    }
}
