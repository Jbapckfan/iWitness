import SwiftUI
import UIKit
import Combine
import UserNotifications

// MARK: - AppDelegate (Background Upload Session)

class AppDelegate: NSObject, UIApplicationDelegate {
    static let backgroundSessionEvent = Notification.Name("BackgroundSessionCompletionHandler")

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        NotificationCenter.default.post(
            name: Self.backgroundSessionEvent,
            object: nil,
            userInfo: ["completionHandler": completionHandler]
        )
    }
}

@main
struct OnTheRecordApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    @StateObject private var appState = AppState()
    @StateObject private var recordingService = RecordingService()
    @StateObject private var uploadService = UploadService()
    @StateObject private var alertService = AlertService()
    @StateObject private var liveStreamService = LiveStreamService()
    @StateObject private var connectivityGuardian = ConnectivityGuardian()
    @StateObject private var locationService = LocationService()
    @StateObject private var witnessBeaconService = WitnessBeaconService.shared
    @StateObject private var appLockService = AppLockService.shared

    @Environment(\.scenePhase) private var scenePhase

    // Watch connectivity
    private let phoneConnectivity = PhoneConnectivityManager.shared
    private let siriManager = SiriShortcutManager.shared
    private let geofenceService = GeofenceService.shared
    private final class CancellableStorage {
        var cancellables = Set<AnyCancellable>()
    }
    private let cancellableStorage = CancellableStorage()

    var body: some Scene {
        WindowGroup {
            if appLockService.isLocked && appLockService.isEnabled {
                AppLockView(lockService: appLockService)
            } else {
                ContentView()
                    .environmentObject(appState)
                    .environmentObject(recordingService)
                    .environmentObject(uploadService)
                    .environmentObject(alertService)
                    .environmentObject(liveStreamService)
                    .environmentObject(connectivityGuardian)
                    .environmentObject(locationService)
                    .environmentObject(witnessBeaconService)
                    .onAppear {
                        setupServices()
                    }
                    .onContinueUserActivity(SiriShortcutManager.activateActivityType) { activity in
                        handleSiriActivate(activity)
                    }
                    .onContinueUserActivity(SiriShortcutManager.pulledOverActivityType) { activity in
                        handleSiriActivate(activity)
                    }
                    .onContinueUserActivity(SiriShortcutManager.safeActivityType) { activity in
                        handleSiriSafe(activity)
                    }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                appLockService.lock()
                if appState.isRecording {
                    postBackgroundRecordingNotification()
                }
            case .active:
                removeBackgroundRecordingNotification()
            default:
                break
            }
        }
    }

    private func setupServices() {
        // Security Hygiene: Wipe any cleartext chunks from crashed sessions immediately
        ChunkWriter.wipeOrphanedChunks()

        // Initialize core services
        recordingService.configure(uploadService: uploadService, liveStreamService: liveStreamService)
        alertService.configure()
        alertService.loadTwilioConfig()
        connectivityGuardian.configure(alertService: alertService)
        witnessBeaconService.configure(uploadService: uploadService)

        // Setup Watch connectivity
        setupWatchConnectivity()

        // Donate Siri shortcuts slightly later to avoid first-launch contention
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            siriManager.donateActivateShortcut()
            siriManager.donatePulledOverShortcut()
            siriManager.donateSafeShortcut()
        }

        // Request location authorization
        locationService.requestAuthorization()

        // Request speech recognition authorization (for live transcription)
        Task {
            await TranscriptionService.shared.requestAuthorization()
        }

        // Listen for Siri notifications
        setupSiriNotifications()

        // Listen for shake escalation events from RecordingService
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("com.ontherecord.shakeEscalation"),
            object: nil,
            queue: .main
        ) { [self] _ in
            Task { @MainActor in
                if let incidentID = appState.currentIncidentID {
                    await alertService.escalateAlert(incidentID: incidentID)
                }
            }
        }

        // Wire background session completion handler from AppDelegate → UploadService
        let uploadService = self.uploadService
        NotificationCenter.default.addObserver(
            forName: AppDelegate.backgroundSessionEvent,
            object: nil,
            queue: .main
        ) { notification in
            if let handler = notification.userInfo?["completionHandler"] as? () -> Void {
                uploadService.backgroundSessionCompletionHandler = handler
            }
        }

        // Defer heavy config/keychain lifting to background
        Task.detached(priority: .userInitiated) {
            Self.migrateSecretsToKeychain()
            await Self.loadSavedUploadDestinationsBackground(uploadService: uploadService)
        }

        // Wire geofence auto-record: when entering a monitored zone, activate witness mode
        geofenceService.onZoneEntered = { [self] zone in
            debugLog("[OnTheRecord] Geofence triggered: \(zone.name)")
            Task { @MainActor in
                await activateWitnessMode()
            }
        }

        // Listen for auto-stop triggered by max recording duration
        NotificationCenter.default.addObserver(
            forName: .autoStopTriggered, object: nil, queue: .main
        ) { [self] _ in
            Task { @MainActor in
                debugLog("[OnTheRecord] Auto-stop triggered after \(appState.maxRecordingDuration.rawValue)")
                await markSafe()
            }
        }

        // Load audio enhancement settings
        AudioEnhancementService.shared.loadSettings()

        // Pre-warm camera for faster activation
        recordingService.prewarmCameraSession()

        // Auto-record on launch if enabled
        if UserDefaults.standard.bool(forKey: "auto_record_on_launch") {
            Task { @MainActor in
                await activateWitnessMode()
            }
        }
    }

    private func setupWatchConnectivity() {
        phoneConnectivity.activate()

        // Handle commands from Watch
        phoneConnectivity.onActivateCommand = { [self] in
            Task { @MainActor in
                await activateWitnessMode()
            }
        }

        phoneConnectivity.onSafeCommand = { [self] in
            Task { @MainActor in
                await markSafe()
            }
        }

        phoneConnectivity.onEscalateCommand = { [self] in
            Task { @MainActor in
                if let incidentID = appState.currentIncidentID {
                    await alertService.escalateAlert(incidentID: incidentID)
                }
            }
        }
    }

    private func setupSiriNotifications() {
        NotificationCenter.default.addObserver(
            forName: .siriActivateWitness,
            object: nil,
            queue: .main
        ) { [self] _ in
            Task { @MainActor in
                await activateWitnessMode()
            }
        }

        NotificationCenter.default.addObserver(
            forName: .siriMarkSafe,
            object: nil,
            queue: .main
        ) { [self] _ in
            Task { @MainActor in
                await markSafe()
            }
        }
    }

    // Permission requests are handled in Onboarding

    // MARK: - Migration
    private static func migrateSecretsToKeychain() {
        // Making static to avoid capturing self, though not strictly necessary
        // NAS password
        if let legacyNAS = UserDefaults.standard.string(forKey: "nas_password"),
           !legacyNAS.isEmpty,
           KeychainHelper.shared.read(service: "OnTheRecord", account: "nas_password") == nil {
            _ = KeychainHelper.shared.save(service: "OnTheRecord", account: "nas_password", value: legacyNAS)
            UserDefaults.standard.removeObject(forKey: "nas_password")
        }

        // Cloud secret key
        if let legacyCloud = UserDefaults.standard.string(forKey: "cloud_secret_key"),
           !legacyCloud.isEmpty,
           KeychainHelper.shared.read(service: "OnTheRecord", account: "cloud_secret_key") == nil {
            _ = KeychainHelper.shared.save(service: "OnTheRecord", account: "cloud_secret_key", value: legacyCloud)
            UserDefaults.standard.removeObject(forKey: "cloud_secret_key")
        }

        // Safe PIN
        if let legacySafePin = UserDefaults.standard.string(forKey: "safe_pin"),
           !legacySafePin.isEmpty,
           KeychainHelper.shared.read(service: "OnTheRecord", account: "safe_pin") == nil {
            _ = KeychainHelper.shared.save(service: "OnTheRecord", account: "safe_pin", value: legacySafePin)
            UserDefaults.standard.removeObject(forKey: "safe_pin")
        }

        // Duress PIN
        if let legacyDuressPin = UserDefaults.standard.string(forKey: "duress_pin"),
           !legacyDuressPin.isEmpty,
           KeychainHelper.shared.read(service: "OnTheRecord", account: "duress_pin") == nil {
            _ = KeychainHelper.shared.save(service: "OnTheRecord", account: "duress_pin", value: legacyDuressPin)
            UserDefaults.standard.removeObject(forKey: "duress_pin")
        }

        // Streaming R2 access key
        if let legacyR2Access = UserDefaults.standard.string(forKey: "stream_r2_access_key"),
           !legacyR2Access.isEmpty,
           KeychainHelper.shared.read(service: "OnTheRecord", account: "stream_r2_access_key") == nil {
            _ = KeychainHelper.shared.save(service: "OnTheRecord", account: "stream_r2_access_key", value: legacyR2Access)
            UserDefaults.standard.removeObject(forKey: "stream_r2_access_key")
        }

        // Streaming R2 secret key
        if let legacyR2Secret = UserDefaults.standard.string(forKey: "stream_r2_secret_key"),
           !legacyR2Secret.isEmpty,
           KeychainHelper.shared.read(service: "OnTheRecord", account: "stream_r2_secret_key") == nil {
            _ = KeychainHelper.shared.save(service: "OnTheRecord", account: "stream_r2_secret_key", value: legacyR2Secret)
            UserDefaults.standard.removeObject(forKey: "stream_r2_secret_key")
        }

        // Streaming custom server password
        if let legacyCustomPass = UserDefaults.standard.string(forKey: "stream_custom_password"),
           !legacyCustomPass.isEmpty,
           KeychainHelper.shared.read(service: "OnTheRecord", account: "stream_custom_password") == nil {
            _ = KeychainHelper.shared.save(service: "OnTheRecord", account: "stream_custom_password", value: legacyCustomPass)
            UserDefaults.standard.removeObject(forKey: "stream_custom_password")
        }
    }

    private static func loadSavedUploadDestinationsBackground(uploadService: UploadService) async {
        // Load NAS configuration
        var nasConfig: (URL, String, String)?
        if let nasURLString = UserDefaults.standard.string(forKey: "nas_url"),
           let nasURL = URL(string: nasURLString) {
            let username = UserDefaults.standard.string(forKey: "nas_username") ?? ""
            let password = KeychainHelper.shared.read(service: "OnTheRecord", account: "nas_password") ?? ""
            nasConfig = (nasURL, username, password)
        }

        // Load Cloud (R2) configuration
        var cloudConfig: (String, String, String, String)?
        if let accountID = UserDefaults.standard.string(forKey: "cloud_account_id"),
           let bucketName = UserDefaults.standard.string(forKey: "cloud_bucket"),
           let accessKey = UserDefaults.standard.string(forKey: "cloud_access_key"),
           let secretKey = KeychainHelper.shared.read(service: "OnTheRecord", account: "cloud_secret_key") {
            cloudConfig = (accountID, bucketName, accessKey, secretKey)
        }
        
        // Update Service on Main Actor
        await MainActor.run {
            if let (url, user, pass) = nasConfig {
                uploadService.addNASDestination(url: url, username: user, password: pass)
                debugLog("[OnTheRecord] Loaded NAS destination: \(url)")
            }
            
            if let (acc, bucket, access, secret) = cloudConfig {
                uploadService.addR2Destination(
                    accountID: acc,
                    bucketName: bucket,
                    accessKeyID: access,
                    secretAccessKey: secret
                )
                debugLog("[OnTheRecord] Loaded R2 cloud destination")
            }
        }
    }

    // MARK: - Siri Handlers

    private func handleSiriActivate(_ activity: NSUserActivity) {
        Task { @MainActor in
            await activateWitnessMode()
        }
    }

    private func handleSiriSafe(_ activity: NSUserActivity) {
        Task { @MainActor in
            await markSafe()
        }
    }

    // MARK: - Core Actions

    @MainActor
    private func activateWitnessMode() async {
        // Run preflight checks
        let preflight = PreflightCheckService()
        let report = await preflight.runChecks(alertService: alertService, uploadService: uploadService)

        if report.hasBlockers {
            debugLog("[OnTheRecord] Activation blocked by preflight: \(report.blockers.map(\.message).joined(separator: ", "))")
            return
        }

        // Activate app state
        appState.activateICEMode()
        IncidentHistoryService.shared.registerIncident(id: appState.currentIncidentID ?? "unknown")
        // Apply stealth start in blackout if enabled
        if UserDefaults.standard.bool(forKey: "stealth_start_blackout") {
            appState.isBlackoutOn = true
        }

        // Start location tracking and feed updates into appState
        locationService.startTracking()
        locationService.$currentLocation
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak appState] location in
                appState?.currentLocation = location
            }
            .store(in: &cancellableStorage.cancellables)

        // Start looking for nearby witnesses to offload data to
        witnessBeaconService.startBroadcastingMode()

        // Start recording
        do {
            try await recordingService.startRecording(
                incidentID: appState.currentIncidentID ?? "unknown",
                quality: appState.currentQuality
            )

            // Send alerts (use Twilio if configured, otherwise SMS URL)
            if alertService.useTwilio {
                await alertService.sendEmergencyAlertViaTwilio(
                    incidentID: appState.currentIncidentID ?? "unknown",
                    location: appState.currentLocation
                )
            } else {
                await alertService.sendEmergencyAlert(
                    incidentID: appState.currentIncidentID ?? "unknown",
                    location: appState.currentLocation,
                    streamURL: nil
                )
            }

            // Notify Watch
            phoneConnectivity.sendRecordingStarted()

            // Start Live Activity (best-effort)
            LiveActivityManager.shared.start(incidentID: appState.currentIncidentID ?? "unknown")

        } catch {
            debugLog("[OnTheRecord] Failed to start recording: \(error)")
        }
    }

    @MainActor
    private func markSafe() async {
        // Stop recording
        await recordingService.stopRecording()

        // Stop location tracking
        locationService.stopTracking()

        // Stop P2P
        witnessBeaconService.stopAll()

        // Send safe signal
        await alertService.sendSafeSignal()

        // Track incident for retention management
        let duration = appState.recordingDuration
        let bytesPerSec = Double(appState.currentQuality.bitrate) / 8.0
        let estimatedBytes = Int64(duration * bytesPerSec * 2) // x2 for dual camera
        IncidentHistoryService.shared.markIncidentStopped(
            id: appState.currentIncidentID ?? "unknown",
            estimatedBytes: estimatedBytes
        )
        IncidentHistoryService.shared.promoteEligibleIncidents()

        // Update state
        appState.markSafe()

        // Notify Watch
        phoneConnectivity.sendRecordingStopped()

        // Reset after delay
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        appState.reset()

        // End Live Activity
        LiveActivityManager.shared.end()
    }

    // MARK: - Background Recording Notification

    private static let backgroundNotificationID = "com.ontherecord.backgroundRecording"

    private func postBackgroundRecordingNotification() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Recording Active"
            content.body = "On The Record is still recording in the background. Tap to return."
            content.sound = nil
            content.interruptionLevel = .passive

            // Fire immediately (1 second trigger)
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            let request = UNNotificationRequest(
                identifier: Self.backgroundNotificationID,
                content: content,
                trigger: trigger
            )
            center.add(request) { error in
                if let error = error {
                    debugLog("[OnTheRecord] Background notification failed: \(error)")
                }
            }
        }
    }

    private func removeBackgroundRecordingNotification() {
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: [Self.backgroundNotificationID])
        center.removePendingNotificationRequests(withIdentifiers: [Self.backgroundNotificationID])
    }
}
