import SwiftUI

// MARK: - Design System

struct DesignSystem {
    // Bold, high-contrast colors for emergency visibility
    static let witnessRed = Color(red: 0.9, green: 0.2, blue: 0.2)
    static let safeGreen = Color(red: 0.2, green: 0.8, blue: 0.3)
    static let warningOrange = Color(red: 1.0, green: 0.6, blue: 0.0)
    static let errorRed = Color(red: 0.8, green: 0.1, blue: 0.1)
    static let backgroundDark = Color(red: 0.05, green: 0.05, blue: 0.05)

    // Spacing
    static let sectionSpacing: CGFloat = 40
    static let buttonPadding: CGFloat = 24
    static let cornerRadius: CGFloat = 20
    static let iconSize: CGFloat = 28
}

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var recordingService: RecordingService
    @EnvironmentObject var uploadService: UploadService
    @State private var showingSettings = false
    @State private var showingOnboarding = false
    @State private var showingSavedConfirmation = false

    var body: some View {
        ZStack {
            if appState.isICEModeActive {
                RecordingView()
            } else if showingSavedConfirmation {
                RecordingSavedView(isShowing: $showingSavedConfirmation)
            } else {
                HomeView(
                    showingSettings: $showingSettings,
                    showingOnboarding: $showingOnboarding
                )
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showingOnboarding) {
            OnboardingView()
        }
        .onAppear {
            checkFirstLaunch()
        }
        .onChange(of: appState.recordingMode) { oldValue, newValue in
            if oldValue == .recording && newValue == .uploading {
                showingSavedConfirmation = true
            }
        }
    }

    private func checkFirstLaunch() {
        if !UserDefaults.standard.bool(forKey: "onboarding_complete") {
            showingOnboarding = true
        }
    }
}

// MARK: - Recording Saved Confirmation

struct RecordingSavedView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var uploadService: UploadService
    @EnvironmentObject var recordingService: RecordingService
    @Binding var isShowing: Bool

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                // Success icon
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(DesignSystem.safeGreen)

                VStack(spacing: 8) {
                    Text("RECORDING SAVED")
                        .font(.system(size: 24, weight: .bold))

                    Text("Your footage is safe")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }

                // Storage status
                VStack(spacing: 12) {
                    // Photos backup - Front camera
                    if recordingService.isDualCameraSupported {
                        HStack(spacing: 12) {
                            Image(systemName: recordingService.frontSavedToPhotos ? "checkmark.circle.fill" : "arrow.clockwise")
                                .foregroundColor(recordingService.frontSavedToPhotos ? DesignSystem.safeGreen : .orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Front Camera")
                                    .font(.system(size: 14, weight: .semibold))
                                Text(recordingService.frontSavedToPhotos ? "Saved to Photos" : "Saving...")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }

                        // Photos backup - Back camera
                        HStack(spacing: 12) {
                            Image(systemName: recordingService.backSavedToPhotos ? "checkmark.circle.fill" : "arrow.clockwise")
                                .foregroundColor(recordingService.backSavedToPhotos ? DesignSystem.safeGreen : .orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Back Camera")
                                    .font(.system(size: 14, weight: .semibold))
                                Text(recordingService.backSavedToPhotos ? "Saved to Photos" : "Saving...")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                    } else {
                        // Single camera mode
                        HStack(spacing: 12) {
                            Image(systemName: recordingService.savedToPhotos ? "checkmark.circle.fill" : "arrow.clockwise")
                                .foregroundColor(recordingService.savedToPhotos ? DesignSystem.safeGreen : .orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Photos Library")
                                    .font(.system(size: 14, weight: .semibold))
                                Text(recordingService.savedToPhotos ? "Saved" : "Saving...")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                    }

                    Divider()

                    // NAS backup
                    HStack(spacing: 12) {
                        Image(systemName: uploadService.queueDepth == 0 ? "checkmark.circle.fill" : "arrow.clockwise")
                            .foregroundColor(uploadService.queueDepth == 0 ? DesignSystem.safeGreen : .orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Secure Offsite Backup")
                                .font(.system(size: 14, weight: .semibold))
                            Text(uploadService.queueDepth == 0 ? "Complete" : "\(uploadService.queueDepth) segments uploading...")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                }
                .padding(16)
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding(.horizontal, 24)

                Spacer()

                // Done button
                Button {
                    isShowing = false
                    appState.reset()
                } label: {
                    Text("DONE")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(DesignSystem.safeGreen)
                        .cornerRadius(16)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
    }
}

// MARK: - Home View

struct HomeView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var recordingService: RecordingService
    @EnvironmentObject var alertService: AlertService
    @EnvironmentObject var uploadService: UploadService
    @Binding var showingSettings: Bool
    @Binding var showingOnboarding: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [Color(.systemBackground), Color(.systemGray6)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 24) {
                    // CRITICAL: Contact/Storage warnings at TOP
                    SetupWarningsView(showingSettings: $showingSettings)

                    Spacer()

                    // System status
                    SystemStatusView()

                    Spacer()

                    // Main activation button
                    ActivationButton()

                    // Subtitle instruction
                    Text("TAP TO ACTIVATE")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.secondary)
                        .tracking(2)

                    Spacer()

                    // Bottom status bar
                    ReadinessBar()
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            .navigationTitle("iWitness")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showingOnboarding = true
                    } label: {
                        Image(systemName: "questionmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Setup Warnings (Critical - Top of Screen)

struct SetupWarningsView: View {
    @EnvironmentObject var alertService: AlertService
    @EnvironmentObject var uploadService: UploadService
    @Binding var showingSettings: Bool

    private var hasContacts: Bool {
        !alertService.contacts.isEmpty
    }

    private var hasStorage: Bool {
        UserDefaults.standard.string(forKey: "nas_url") != nil
    }

    var body: some View {
        VStack(spacing: 8) {
            if !hasContacts {
                WarningBanner(
                    icon: "person.2",
                    title: "Add emergency contacts",
                    subtitle: "",
                    action: { showingSettings = true }
                )
            }

            if !hasStorage {
                WarningBanner(
                    icon: "externaldrive",
                    title: "Add backup storage",
                    subtitle: "",
                    action: { showingSettings = true }
                )
            }
        }
    }
}

struct WarningBanner: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(.secondary)

                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)

                Spacer()

                Text("Setup")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.blue)
            }
            .padding(12)
            .background(Color(.systemGray6))
            .cornerRadius(10)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - System Status View

struct SystemStatusView: View {
    @EnvironmentObject var alertService: AlertService
    @EnvironmentObject var uploadService: UploadService

    private var hasContacts: Bool { !alertService.contacts.isEmpty }
    private var hasStorage: Bool { UserDefaults.standard.string(forKey: "nas_url") != nil }

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 24) {
                StatusPill(
                    icon: "person.2.fill",
                    label: hasContacts ? "\(alertService.contacts.count) Contacts" : "No Contacts",
                    isActive: hasContacts
                )

                StatusPill(
                    icon: "externaldrive.fill",
                    label: hasStorage ? "Backup Ready" : "No Storage",
                    isActive: hasStorage
                )
            }

            if uploadService.queueDepth > 0 {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Uploading \(uploadService.queueDepth) pending...")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(DesignSystem.warningOrange)
                }
            }
        }
    }
}

struct StatusPill: View {
    let icon: String
    let label: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
            Text(label)
                .font(.system(size: 14, weight: .semibold))
        }
        .foregroundColor(isActive ? DesignSystem.safeGreen : .secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(isActive ? DesignSystem.safeGreen.opacity(0.15) : Color(.systemGray5))
        )
    }
}

// MARK: - Pressable Button Style

struct PressableButtonStyle: ButtonStyle {
    @Binding var isPressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, newValue in
                isPressed = newValue
            }
    }
}

// MARK: - Activation Button

struct ActivationButton: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var recordingService: RecordingService
    @EnvironmentObject var alertService: AlertService
    @EnvironmentObject var uploadService: UploadService

    @State private var isPressed = false
    @State private var isActivating = false
    @State private var pulseScale: CGFloat = 1.0

    var body: some View {
        Button {
            activateWitnessMode()
        } label: {
            ZStack {
                // Outer pulse ring
                Circle()
                    .stroke(DesignSystem.witnessRed.opacity(0.3), lineWidth: 4)
                    .frame(width: 260, height: 260)
                    .scaleEffect(pulseScale)

                // Main button
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [
                                DesignSystem.witnessRed,
                                DesignSystem.witnessRed.opacity(0.8)
                            ]),
                            center: .center,
                            startRadius: 0,
                            endRadius: 120
                        )
                    )
                    .frame(width: 240, height: 240)
                    .shadow(color: DesignSystem.witnessRed.opacity(0.6), radius: isPressed ? 30 : 20)
                    .scaleEffect(isPressed ? 0.95 : 1.0)

                // Content
                if isActivating {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)
                        Text("ACTIVATING")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "video.fill")
                            .font(.system(size: 56, weight: .medium))

                        Text("WITNESS")
                            .font(.system(size: 28, weight: .heavy))
                    }
                    .foregroundColor(.white)
                }
            }
        }
        .buttonStyle(PressableButtonStyle(isPressed: $isPressed))
        .disabled(isActivating)
        .accessibilityLabel("Activate Witness Mode")
        .accessibilityHint("Tap to start recording and send alerts to your emergency contacts")
        .onAppear {
            startPulseAnimation()
        }
    }

    private func startPulseAnimation() {
        withAnimation(
            .easeInOut(duration: 2.0)
            .repeatForever(autoreverses: true)
        ) {
            pulseScale = 1.15
        }
    }

    private func activateWitnessMode() {
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()

        // Show activating state
        withAnimation(.easeInOut(duration: 0.2)) {
            isActivating = true
        }

        // Activate
        appState.activateICEMode()

        // Start recording
        Task {
            do {
                try await recordingService.startRecording(
                    incidentID: appState.currentIncidentID ?? "unknown",
                    quality: appState.currentQuality
                )

                // Send alerts
                await alertService.sendEmergencyAlert(
                    incidentID: appState.currentIncidentID ?? "unknown",
                    location: appState.currentLocation,
                    streamURL: nil
                )

                // Success haptic
                let successGenerator = UINotificationFeedbackGenerator()
                successGenerator.notificationOccurred(.success)

            } catch {
                print("[iWitness] Failed to start recording: \(error)")

                // Error haptic
                let errorGenerator = UINotificationFeedbackGenerator()
                errorGenerator.notificationOccurred(.error)

                withAnimation {
                    isActivating = false
                }
            }
        }
    }
}

// MARK: - Readiness Bar

struct ReadinessBar: View {
    @EnvironmentObject var alertService: AlertService

    private var hasContacts: Bool { !alertService.contacts.isEmpty }
    private var hasStorage: Bool { UserDefaults.standard.string(forKey: "nas_url") != nil }

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(DesignSystem.safeGreen)
                .frame(width: 12, height: 12)

            Text("READY TO RECORD")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(DesignSystem.safeGreen)
                .tracking(1)

            Spacer()

            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 20))
                .foregroundColor(DesignSystem.safeGreen)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(DesignSystem.safeGreen.opacity(0.1))
        )
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
        .environmentObject(RecordingService())
        .environmentObject(UploadService())
        .environmentObject(AlertService())
}
