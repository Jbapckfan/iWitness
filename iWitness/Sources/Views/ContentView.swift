import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var recordingService: RecordingService
    @EnvironmentObject var uploadService: UploadService
    @State private var showingSettings = false
    @State private var showingOnboarding = false
    @State private var showingSavedConfirmation = false
    
    // Calculator Camouflage
    @State private var isCamouflageUnlocked = false
    
    private var isCamouflageEnabled: Bool {
        UserDefaults.standard.bool(forKey: "calculator_camouflage")
    }

    var body: some View {
        ZStack {
            // Show calculator camouflage if enabled and not unlocked
            if isCamouflageEnabled && !isCamouflageUnlocked {
                CalculatorCamouflageView(isUnlocked: $isCamouflageUnlocked)
                    .transition(.opacity)
            } else {
                // Normal app flow
                mainContent
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isCamouflageUnlocked)
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
    
    @ViewBuilder
    private var mainContent: some View {
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

    @State private var isViewAppeared = false
    @State private var iconScale: CGFloat = 0.5
    @State private var glowRadius: CGFloat = 10

    var body: some View {
        ZStack {
            // Premium success glow background
            SuccessGlowBackground()

            VStack(spacing: Spacing.lg) {
                Spacer()

                // Success icon with entrance animation
                ZStack {
                    // Glow behind icon
                    Circle()
                        .fill(Colors.safeGreen.opacity(0.2))
                        .frame(width: 120, height: 120)
                        .blur(radius: glowRadius)

                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 80))
                        .foregroundColor(Colors.safeGreen)
                        .scaleEffect(iconScale)
                }
                .onAppear {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                        iconScale = 1.0
                    }
                    withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                        glowRadius = 25
                    }
                }

                VStack(spacing: Spacing.xs) {
                    Text("RECORDING SAVED")
                        .font(Typography.headline1)
                        .tracking(1)

                    Text("Your footage is safe")
                        .font(Typography.bodyLarge)
                        .foregroundColor(.secondary)
                }
                .fadeScaleEntrance(isPresented: isViewAppeared, delay: 0.2)

                // Storage status in glass card
                GlassCard(material: .thinMaterial, padding: Spacing.md) {
                    VStack(spacing: Spacing.sm) {
                        // Photos backup - Front camera
                        if recordingService.isDualCameraSupported {
                            SaveStatusRow(
                                title: "Front Camera",
                                subtitle: recordingService.frontSavedToPhotos ? "Saved to Photos" : "Saving...",
                                isComplete: recordingService.frontSavedToPhotos
                            )

                            SaveStatusRow(
                                title: "Back Camera",
                                subtitle: recordingService.backSavedToPhotos ? "Saved to Photos" : "Saving...",
                                isComplete: recordingService.backSavedToPhotos
                            )
                        } else {
                            SaveStatusRow(
                                title: "Photos Library",
                                subtitle: recordingService.savedToPhotos ? "Saved" : "Saving...",
                                isComplete: recordingService.savedToPhotos
                            )
                        }

                        Divider()
                            .opacity(0.3)

                        SaveStatusRow(
                            title: "Secure Offsite Backup",
                            subtitle: uploadService.queueDepth == 0 ? "Complete" : "\(uploadService.queueDepth) segments uploading...",
                            isComplete: uploadService.queueDepth == 0
                        )
                    }
                }
                .padding(.horizontal, Spacing.lg)
                .staggeredEntrance(isPresented: isViewAppeared, index: 2)

                Spacer()

                // Done button
                PremiumPrimaryButton(
                    title: "DONE",
                    icon: nil,
                    color: Colors.safeGreen
                ) {
                    isShowing = false
                    appState.reset()
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.bottom, Spacing.xl)
                .staggeredEntrance(isPresented: isViewAppeared, index: 3)
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isViewAppeared = true
            }
        }
    }
}

// MARK: - Save Status Row

struct SaveStatusRow: View {
    let title: String
    let subtitle: String
    let isComplete: Bool

    var body: some View {
        HStack(spacing: Spacing.sm) {
            if isComplete {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(Colors.safeGreen)
                    .font(.system(size: 18))
            } else {
                ProgressView()
                    .scaleEffect(0.8)
                    .tint(Colors.warningOrange)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typography.bodyMedium)
                    .fontWeight(.semibold)
                Text(subtitle)
                    .font(Typography.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }
}

// MARK: - Home View

struct HomeView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var recordingService: RecordingService
    @EnvironmentObject var alertService: AlertService
    @EnvironmentObject var uploadService: UploadService
    @EnvironmentObject var liveStreamService: LiveStreamService
    @Binding var showingSettings: Bool
    @Binding var showingOnboarding: Bool

    @State private var isViewAppeared = false

    var body: some View {
        NavigationStack {
            ZStack {
                // Premium ambient background
                AmbientOrbsBackground(accentColor: DesignSystem.witnessRed, intensity: 0.12)

                VStack(spacing: Spacing.lg) {
                    // CRITICAL: Contact/Storage warnings at TOP
                    SetupWarningsView(showingSettings: $showingSettings)
                        .staggeredEntrance(isPresented: isViewAppeared, index: 0)

                    Spacer()

                    // System status in glass card
                    SystemStatusView()
                        .staggeredEntrance(isPresented: isViewAppeared, index: 1)

                    Spacer()

                    // Main activation button
                    ActivationButton()
                        .fadeScaleEntrance(isPresented: isViewAppeared, delay: 0.15)

                    // Subtitle instruction
                    Text("TAP TO ACTIVATE")
                        .font(Typography.label)
                        .foregroundColor(.secondary)
                        .tracking(2)
                        .staggeredEntrance(isPresented: isViewAppeared, index: 3)

                    Spacer()

                    // Bottom status bar
                    ReadinessBar()
                        .staggeredEntrance(isPresented: isViewAppeared, index: 4)
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.vertical, Spacing.md)
            }
            .navigationTitle("iWitness")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    PremiumIconButton(icon: "questionmark.circle.fill", size: 36, style: .glass) {
                        showingOnboarding = true
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    PremiumIconButton(icon: "gearshape.fill", size: 36, style: .glass) {
                        showingSettings = true
                    }
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isViewAppeared = true
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
        VStack(spacing: Spacing.xs) {
            if !hasContacts {
                WarningBanner(
                    icon: "person.2.fill",
                    title: "Add emergency contacts",
                    action: { showingSettings = true }
                )
            }

            if !hasStorage {
                WarningBanner(
                    icon: "externaldrive.fill",
                    title: "Add backup storage",
                    action: { showingSettings = true }
                )
            }
        }
    }
}

struct WarningBanner: View {
    let icon: String
    let title: String
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Colors.warningOrange)

                Text(title)
                    .font(Typography.bodyMedium)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)

                Spacer()

                HStack(spacing: Spacing.xxs) {
                    Text("Setup")
                        .font(Typography.caption)
                        .fontWeight(.semibold)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundColor(Colors.warningOrange)
            }
            .padding(Spacing.sm)
            .glassCard(padding: 0, showBorder: true)
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.Radius.lg)
                    .stroke(Colors.warningOrange.opacity(0.3), lineWidth: 1)
            )
            .scaleEffect(isPressed ? 0.98 : 1.0)
        }
        .buttonStyle(PremiumPressStyle(isPressed: $isPressed))
    }
}

// MARK: - System Status View

struct SystemStatusView: View {
    @EnvironmentObject var alertService: AlertService
    @EnvironmentObject var uploadService: UploadService

    private var hasContacts: Bool { !alertService.contacts.isEmpty }
    private var hasStorage: Bool { UserDefaults.standard.string(forKey: "nas_url") != nil }

    var body: some View {
        VStack(spacing: Spacing.md) {
            HStack(spacing: Spacing.md) {
                PremiumStatusPill(
                    icon: "person.2.fill",
                    label: hasContacts ? "\(alertService.contacts.count) Contacts" : "No Contacts",
                    isActive: hasContacts
                )

                PremiumStatusPill(
                    icon: "externaldrive.fill",
                    label: hasStorage ? "Backup Ready" : "No Storage",
                    isActive: hasStorage
                )
            }

            if uploadService.queueDepth > 0 {
                GlassCapsule {
                    HStack(spacing: Spacing.xs) {
                        ProgressView()
                            .scaleEffect(0.7)
                            .tint(Colors.warningOrange)
                        Text("Uploading \(uploadService.queueDepth) pending...")
                            .font(Typography.caption)
                            .foregroundColor(Colors.warningOrange)
                    }
                }
            }
        }
        .glassCard(material: .ultraThinMaterial, cornerRadius: Spacing.Radius.lg, padding: Spacing.md)
    }
}

struct PremiumStatusPill: View {
    let icon: String
    let label: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
            Text(label)
                .font(Typography.caption)
                .fontWeight(.semibold)
        }
        .foregroundColor(isActive ? Colors.safeGreen : .secondary)
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xs)
        .background(
            Capsule()
                .fill(isActive ? Colors.safeGreen.opacity(0.2) : Color.white.opacity(0.1))
        )
        .overlay(
            Capsule()
                .stroke(isActive ? Colors.safeGreen.opacity(0.4) : Color.clear, lineWidth: 1)
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
    @EnvironmentObject var liveStreamService: LiveStreamService

    @State private var isPressed = false
    @State private var isActivating = false
    @State private var pulseScale: CGFloat = 1.0
    @State private var glowIntensity: CGFloat = 0.4

    var body: some View {
        Button {
            activateWitnessMode()
        } label: {
            ZStack {
                // Outer glow ring
                Circle()
                    .fill(DesignSystem.witnessRed.opacity(0.15))
                    .frame(width: 280, height: 280)
                    .blur(radius: 20)
                    .scaleEffect(pulseScale)

                // Outer pulse ring
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                DesignSystem.witnessRed.opacity(0.5),
                                DesignSystem.witnessRed.opacity(0.2)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 3
                    )
                    .frame(width: 260, height: 260)
                    .scaleEffect(pulseScale)

                // Main button with premium gradient
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [
                                DesignSystem.witnessRed,
                                DesignSystem.witnessRed.opacity(0.85)
                            ]),
                            center: .center,
                            startRadius: 0,
                            endRadius: 120
                        )
                    )
                    .frame(width: 240, height: 240)
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.4), Color.white.opacity(0.1)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 2
                            )
                    )
                    .shadow(color: DesignSystem.witnessRed.opacity(glowIntensity), radius: isPressed ? 35 : 25, y: 0)
                    .scaleEffect(isPressed ? 0.95 : 1.0)

                // Content
                if isActivating {
                    VStack(spacing: Spacing.sm) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)
                        Text("ACTIVATING")
                            .font(Typography.headline3)
                            .foregroundColor(.white)
                    }
                } else {
                    VStack(spacing: Spacing.sm) {
                        Image(systemName: "video.fill")
                            .font(.system(size: 56, weight: .medium))

                        Text("WITNESS")
                            .font(.system(size: 28, weight: .heavy))
                            .tracking(1)
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
            startGlowAnimation()
        }
    }

    private func startPulseAnimation() {
        withAnimation(
            .easeInOut(duration: 2.0)
            .repeatForever(autoreverses: true)
        ) {
            pulseScale = 1.12
        }
    }

    private func startGlowAnimation() {
        withAnimation(
            .easeInOut(duration: 1.5)
            .repeatForever(autoreverses: true)
        ) {
            glowIntensity = 0.6
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

        let incidentID = appState.currentIncidentID ?? "unknown"

        // Start recording and streaming
        Task {
            do {
                // 1. Start recording (saves to device + uploads chunks to NAS)
                try await recordingService.startRecording(
                    incidentID: incidentID,
                    quality: appState.currentQuality
                )

                // 2. Start Live Activity for Dynamic Island
                LiveActivityManager.shared.start(incidentID: incidentID)

                // 3. Start live stream if configured (generates shareable URL)
                var streamURLString: String? = nil
                if liveStreamService.isConfigured {
                    do {
                        let streamURL = try await liveStreamService.startStream(incidentID: incidentID)
                        streamURLString = streamURL.absoluteString
                        print("[iWitness] Live stream started: \(streamURLString ?? "none")")
                    } catch {
                        print("[iWitness] Live stream failed (continuing without): \(error)")
                        // Continue without live stream - recording still works
                    }
                }

                // 4. Send alerts to contacts (includes live stream URL if available)
                await alertService.sendEmergencyAlert(
                    incidentID: incidentID,
                    location: appState.currentLocation,
                    streamURL: streamURLString
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

    @State private var pulseOpacity: Double = 0.8

    var body: some View {
        TintedGlassCard(tintColor: Colors.safeGreen, tintOpacity: 0.15, padding: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                PulsingIndicator(color: Colors.safeGreen, size: 10)

                Text("READY TO RECORD")
                    .font(Typography.label)
                    .foregroundColor(Colors.safeGreen)
                    .tracking(1)

                Spacer()

                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Colors.safeGreen)
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
        .environmentObject(RecordingService())
        .environmentObject(UploadService())
        .environmentObject(AlertService())
}
