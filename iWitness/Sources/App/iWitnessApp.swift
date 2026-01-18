import SwiftUI

@main
struct iWitnessApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var recordingService = RecordingService()
    @StateObject private var uploadService = UploadService()
    @StateObject private var alertService = AlertService()
    @StateObject private var liveStreamService = LiveStreamService()
    @StateObject private var connectivityGuardian = ConnectivityGuardian()

    // Watch connectivity
    private let phoneConnectivity = PhoneConnectivityManager.shared
    private let siriManager = SiriShortcutManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(recordingService)
                .environmentObject(uploadService)
                .environmentObject(alertService)
                .environmentObject(liveStreamService)
                .environmentObject(connectivityGuardian)
                .onAppear {
                    setupServices()
                }
                .onContinueUserActivity(SiriShortcutManager.activateActivityType) { activity in
                    handleSiriActivate(activity)
                }
                .onContinueUserActivity(SiriShortcutManager.safeActivityType) { activity in
                    handleSiriSafe(activity)
                }
        }
    }

    private func setupServices() {
        // Initialize core services
        recordingService.configure(uploadService: uploadService, liveStreamService: liveStreamService)
        alertService.configure()
        alertService.loadTwilioConfig()
        connectivityGuardian.configure(alertService: alertService)

        // Load saved upload destinations
        migrateSecretsToKeychain()
        loadSavedUploadDestinations()

        // Setup Watch connectivity
        setupWatchConnectivity()

        // Donate Siri shortcuts slightly later to avoid first-launch contention
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            siriManager.donateActivateShortcut()
            siriManager.donateSafeShortcut()
        }

        // Listen for Siri notifications
        setupSiriNotifications()

        // Defer permission prompts to onboarding flow to avoid first-launch UI contention
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
    private func migrateSecretsToKeychain() {
        // NAS password
        if let legacyNAS = UserDefaults.standard.string(forKey: "nas_password"),
           !legacyNAS.isEmpty,
           KeychainHelper.shared.read(service: "iWitness", account: "nas_password") == nil {
            _ = KeychainHelper.shared.save(service: "iWitness", account: "nas_password", value: legacyNAS)
            UserDefaults.standard.removeObject(forKey: "nas_password")
        }

        // Cloud secret key
        if let legacyCloud = UserDefaults.standard.string(forKey: "cloud_secret_key"),
           !legacyCloud.isEmpty,
           KeychainHelper.shared.read(service: "iWitness", account: "cloud_secret_key") == nil {
            _ = KeychainHelper.shared.save(service: "iWitness", account: "cloud_secret_key", value: legacyCloud)
            UserDefaults.standard.removeObject(forKey: "cloud_secret_key")
        }
    }

    private func loadSavedUploadDestinations() {
        // Load NAS configuration from UserDefaults
        if let nasURLString = UserDefaults.standard.string(forKey: "nas_url"),
           let nasURL = URL(string: nasURLString) {
            let username = UserDefaults.standard.string(forKey: "nas_username") ?? ""
            let password = KeychainHelper.shared.read(service: "iWitness", account: "nas_password") ?? ""
            uploadService.addNASDestination(url: nasURL, username: username, password: password)
            print("[iWitness] Loaded NAS destination: \(nasURLString)")
        }

        // Load Cloud (R2) configuration if configured
        if let accountID = UserDefaults.standard.string(forKey: "cloud_account_id"),
           let bucketName = UserDefaults.standard.string(forKey: "cloud_bucket"),
           let accessKey = UserDefaults.standard.string(forKey: "cloud_access_key"),
           let secretKey = KeychainHelper.shared.read(service: "iWitness", account: "cloud_secret_key") {
            uploadService.addR2Destination(
                accountID: accountID,
                bucketName: bucketName,
                accessKeyID: accessKey,
                secretAccessKey: secretKey
            )
            print("[iWitness] Loaded R2 cloud destination")
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
        // Activate app state
        appState.activateICEMode()
        // Apply stealth start in blackout if enabled
        if UserDefaults.standard.bool(forKey: "stealth_start_blackout") {
            appState.isBlackoutOn = true
        }

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
            print("[iWitness] Failed to start recording: \(error)")
        }
    }

    @MainActor
    private func markSafe() async {
        // Stop recording
        await recordingService.stopRecording()

        // Send safe signal
        await alertService.sendSafeSignal()

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
}
