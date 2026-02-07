import SwiftUI
import LocalAuthentication

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var recordingService: RecordingService
    @EnvironmentObject var uploadService: UploadService
    @State private var showingSettings = false
    @State private var showingOnboarding = false
    @State private var showingSavedConfirmation = false
    @State private var showingRetentionPrompt = false

    // Calculator Camouflage
    @State private var isCamouflageUnlocked = false
    @State private var isDuressActive = false

    // Superlock State
    @State private var isSuperlocked = false
    @State private var superlockFailureCount = 0
    @State private var showPasscodeFallback = false
    
    private var isCamouflageEnabled: Bool {
        UserDefaults.standard.bool(forKey: "calculator_camouflage")
    }

    var body: some View {
        ZStack {
            // Show calculator camouflage if enabled and not unlocked
            if isCamouflageEnabled && !isCamouflageUnlocked {
                CalculatorCamouflageView(
                    isUnlocked: $isCamouflageUnlocked,
                    isDuressActive: $isDuressActive
                )
                .transition(.opacity)
            } else if isDuressActive {
                // Duress Mode: Show Fake Gallery
                FakeGalleryView()
                    .transition(.opacity)
            } else {
                // Normal app flow
                mainContent
            }
            
            // SUPERLOCK OVERLAY (Highest priority)
            if isSuperlocked {
                Color.black
                    .ignoresSafeArea()
                    .onTapGesture {
                        attemptSuperlockUnlock()
                    }
                    .overlay(alignment: .bottom) {
                        if showPasscodeFallback {
                            Button {
                                attemptPasscodeUnlock()
                            } label: {
                                Text("Use Passcode")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            .padding(.bottom, 60)
                            .accessibilityLabel("Unlock with device passcode")
                        }
                    }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isCamouflageUnlocked)
        .animation(.default, value: isSuperlocked)
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showingOnboarding) {
            OnboardingView()
        }
        .sheet(isPresented: $showingRetentionPrompt) {
            RetentionPromptView()
        }
        .onAppear {
            checkFirstLaunch()
        }
        .onChange(of: appState.recordingMode) { oldValue, newValue in
            if oldValue == .recording && newValue == .uploading {
                showingSavedConfirmation = true
                // Check for old incidents to review after a short delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    if !IncidentHistoryService.shared.incidentsPendingReview.isEmpty {
                        showingRetentionPrompt = true
                    }
                }
            }
        }
        .onReceive(recordingService.$shouldLockScreen) { shouldLock in
            if shouldLock {
                isSuperlocked = true
            }
        }
    }
    
    private func attemptSuperlockUnlock() {
        VaultManager.shared.authenticate { success in
            if success {
                withAnimation {
                    isSuperlocked = false
                    superlockFailureCount = 0
                    showPasscodeFallback = false
                    recordingService.shouldLockScreen = false
                }
            } else {
                superlockFailureCount += 1
                if superlockFailureCount >= 3 {
                    showPasscodeFallback = true
                }
            }
        }
    }

    private func attemptPasscodeUnlock() {
        let context = LAContext()
        context.localizedFallbackTitle = "Enter Passcode"
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            context.evaluatePolicy(.deviceOwnerAuthentication,
                                   localizedReason: "Unlock OnTheRecord") { success, _ in
                DispatchQueue.main.async {
                    if success {
                        withAnimation {
                            isSuperlocked = false
                            superlockFailureCount = 0
                            showPasscodeFallback = false
                            recordingService.shouldLockScreen = false
                        }
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var mainContent: some View {
        if appState.isICEModeActive {
            RecordingView()
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 1.02)),
                    removal: .opacity
                ))
        } else if showingSavedConfirmation {
            RecordingSavedView(isShowing: $showingSavedConfirmation)
                .transition(.opacity)
        } else {
            HomeView(
                showingSettings: $showingSettings,
                showingOnboarding: $showingOnboarding
            )
            .transition(.opacity)
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
    @EnvironmentObject var alertService: AlertService
    @Binding var isShowing: Bool

    @State private var isViewAppeared = false
    @State private var iconScale: CGFloat = 0.5
    @State private var glowRadius: CGFloat = 10
    @State private var showingShareSheet = false
    @State private var pdfURL: URL?
    @State private var isExportingEvidence = false
    @State private var exportURL: URL?

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

                // Generate Incident Report button
                Button {
                    generateIncidentReport()
                } label: {
                    Label("Generate Incident Report", systemImage: "doc.text.fill")
                        .font(Typography.bodyLarge)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.ultraThinMaterial)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .padding(.horizontal, Spacing.lg)
                .staggeredEntrance(isPresented: isViewAppeared, index: 3)

                // Export Evidence Package button
                Button {
                    exportEvidencePackage()
                } label: {
                    HStack {
                        if isExportingEvidence {
                            ProgressView()
                                .tint(.white)
                                .padding(.trailing, 4)
                        }
                        Label("Export Evidence Package", systemImage: "shippingbox.fill")
                    }
                    .font(Typography.bodyLarge)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.ultraThinMaterial)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(isExportingEvidence)
                .padding(.horizontal, Spacing.lg)
                .staggeredEntrance(isPresented: isViewAppeared, index: 3)

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
                .staggeredEntrance(isPresented: isViewAppeared, index: 4)
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isViewAppeared = true
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            if let url = pdfURL {
                ShareSheet(activityItems: [url])
            }
        }
    }

    private func exportEvidencePackage() {
        isExportingEvidence = true
        let incidentID = appState.currentIncidentID ?? "unknown"
        let transcription = TranscriptionService.shared

        Task {
            do {
                let package = try await EvidenceExportService.shared.exportEvidence(
                    incidentID: incidentID,
                    transcriptText: transcription.segments.isEmpty ? nil : transcription.exportAsText()
                )
                await MainActor.run {
                    exportURL = package.zipURL
                    pdfURL = package.zipURL
                    showingShareSheet = true
                    isExportingEvidence = false
                }
                debugLog("[RecordingSaved] Evidence package exported: \(package.fileCount) files, \(package.manifestHash)")
            } catch {
                debugLog("[RecordingSaved] Evidence export failed: \(error)")
                await MainActor.run {
                    isExportingEvidence = false
                }
            }
        }
    }

    private func generateIncidentReport() {
        let encService = EncryptionService()
        let fingerprint: String? = encService.exportSigningPublicKey().map {
            IncidentSummaryService.fingerprint(of: $0)
        }

        let summary = IncidentSummaryService.IncidentSummary(
            incidentID: appState.currentIncidentID ?? "unknown",
            startTime: appState.recordingStartTime ?? Date(),
            endTime: Date(),
            duration: appState.recordingStartTime.map { Date().timeIntervalSince($0) } ?? 0,
            locations: [],
            chunkCount: uploadService.chunksUploaded,
            totalDataSize: 0,
            destinations: uploadService.destinations.map(\.name),
            contacts: alertService.contacts.map(\.displayName),
            deviceInfo: IncidentSummaryService.IncidentSummary.DeviceInfo(
                name: UIDevice.current.name,
                model: UIDevice.current.model,
                osVersion: UIDevice.current.systemVersion
            ),
            signingPublicKeyFingerprint: fingerprint
        )

        if let pdfData = IncidentSummaryService.generatePDF(from: summary),
           let url = IncidentSummaryService.savePDF(pdfData, incidentID: summary.incidentID) {
            pdfURL = url
            showingShareSheet = true
        }
    }
}

// MARK: - Share Sheet (UIKit bridge)

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
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

// MARK: - Home View (Premium Dashboard)

struct HomeView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var recordingService: RecordingService
    @EnvironmentObject var alertService: AlertService
    @EnvironmentObject var uploadService: UploadService
    @EnvironmentObject var liveStreamService: LiveStreamService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var showingSettings: Bool
    @Binding var showingOnboarding: Bool

    @State private var isViewAppeared = false
    @State private var readyOpacity: Double = 0.4

    private var hasContacts: Bool { !alertService.contacts.isEmpty }
    private var hasBackup: Bool { !uploadService.destinations.isEmpty }
    private var contactCount: Int { alertService.contacts.count }

    var body: some View {
        NavigationStack {
            ZStack {
                // Background: Warm ambient with floating orbs
                Color.black.ignoresSafeArea()
                AmbientOrbsBackground(accentColor: Colors.ambientWarm, intensity: 0.12)

                VStack(spacing: 0) {
                    // Header: Clean app name + controls
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("On The Record")
                                .font(Typography.headline0)
                                .foregroundColor(.white)
                            Text("v2.0")
                                .font(Typography.caption)
                                .foregroundColor(.white.opacity(0.35))
                        }
                        .accessibilityLabel("OnTheRecord version 2.0")

                        Spacer()

                        HStack(spacing: 20) {
                            Button { showingOnboarding = true } label: {
                                Image(systemName: "questionmark.circle")
                                    .font(.system(size: 20))
                            }
                            .accessibilityLabel("Help")
                            Button { showingSettings = true } label: {
                                Image(systemName: "gearshape.fill")
                                    .font(.system(size: 20))
                            }
                            .accessibilityLabel("Settings")
                        }
                        .foregroundColor(.white.opacity(0.7))
                    }
                    .padding(.horizontal, Spacing.screenPadding)
                    .padding(.top, Spacing.md)
                    .padding(.bottom, Spacing.sm)
                    .luxuryEntrance(isPresented: isViewAppeared)

                    // Main content
                    ScrollView {
                        VStack(spacing: Spacing.lg) {

                            // No-backup warning (persistent until configured)
                            if !hasBackup {
                                NoBackupBanner(showingSettings: $showingSettings)
                                    .luxuryEntrance(isPresented: isViewAppeared, delay: 0.1)
                            }

                            // System readiness card
                            GlassCard(material: .ultraThinMaterial, padding: Spacing.md) {
                                VStack(spacing: Spacing.sm) {
                                    StatusRow(
                                        icon: "person.2.fill",
                                        label: "Emergency Contacts",
                                        isReady: hasContacts,
                                        detail: hasContacts ? "\(contactCount) configured" : "None configured"
                                    )

                                    Divider().opacity(0.1)

                                    StatusRow(
                                        icon: "externaldrive.fill",
                                        label: "Backup Destination",
                                        isReady: hasBackup,
                                        detail: hasBackup ? "Offsite backup active" : "Not configured"
                                    )

                                    Divider().opacity(0.1)

                                    StatusRow(
                                        icon: "camera.fill",
                                        label: "Camera & Microphone",
                                        isReady: true,
                                        detail: recordingService.isDualCameraSupported ? "Dual camera ready" : "Single camera ready"
                                    )
                                }
                            }
                            .padding(.horizontal, Spacing.screenPadding)
                            .luxuryEntrance(isPresented: isViewAppeared, delay: 0.15)

                            Spacer(minLength: 40)

                            // Activation Core — responsive to screen width
                            GeometryReader { geo in
                                let baseSize = min(geo.size.width, geo.size.height) * 0.65
                                let mainSize = max(baseSize, 180)
                                let ringSize = mainSize * (260.0 / 240.0)
                                let dashSize = mainSize * (290.0 / 240.0)

                                ZStack {
                                    Circle()
                                        .stroke(Color.gray.opacity(0.3), lineWidth: 2)
                                        .frame(width: ringSize, height: ringSize)

                                    if !reduceMotion {
                                        Circle()
                                            .stroke(Color.white.opacity(0.06), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
                                            .frame(width: dashSize, height: dashSize)
                                            .rotationEffect(.degrees(isViewAppeared ? 360 : 0))
                                            .animation(.linear(duration: 20).repeatForever(autoreverses: false), value: isViewAppeared)
                                    }

                                    ActivationButton(buttonSize: mainSize)
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                            .frame(height: 310)
                            .frame(maxWidth: .infinity)

                            // Subtle ready indicator
                            Text("Ready")
                                .font(Typography.bodySmall)
                                .foregroundColor(.white.opacity(readyOpacity))
                                .padding(.top, Spacing.sm)
                                .luxuryEntrance(isPresented: isViewAppeared, delay: 0.3)
                                .onAppear {
                                    guard !reduceMotion else { return }
                                    withAnimation(AnimationPresets.breathe) {
                                        readyOpacity = 0.15
                                    }
                                }
                        }
                        .padding(.vertical)
                    }
                }
            }
            .navigationBarHidden(true)
            .onAppear {
                isViewAppeared = true
            }
        }
    }
}

// MARK: - Status Row

struct StatusRow: View {
    let icon: String
    let label: String
    let isReady: Bool
    var detail: String? = nil

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(isReady ? Colors.safeGreen : Colors.warningOrange)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(Typography.statusLabel)
                    .foregroundColor(.white)
                if let detail {
                    Text(detail)
                        .font(Typography.caption)
                        .foregroundColor(.white.opacity(0.5))
                }
            }

            Spacer()

            Image(systemName: isReady ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 16))
                .foregroundColor(isReady ? Colors.safeGreen.opacity(0.7) : Colors.warningOrange.opacity(0.7))
        }
        .accessibilityLabel("\(label): \(isReady ? "ready" : "not configured")")
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
    var buttonSize: CGFloat = 240

    @EnvironmentObject var appState: AppState
    @EnvironmentObject var recordingService: RecordingService
    @EnvironmentObject var alertService: AlertService
    @EnvironmentObject var uploadService: UploadService
    @EnvironmentObject var liveStreamService: LiveStreamService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isPressed = false
    @State private var isActivating = false
    @State private var pulseScale: CGFloat = 1.0
    @State private var glowIntensity: CGFloat = 0.4

    private var glowSize: CGFloat { buttonSize * (280.0 / 240.0) }
    private var pulseRingSize: CGFloat { buttonSize * (260.0 / 240.0) }
    private var iconSize: CGFloat { max(buttonSize * (56.0 / 240.0), 32) }
    private var textSize: CGFloat { max(buttonSize * (28.0 / 240.0), 18) }

    var body: some View {
        Button {
            activateWitnessMode()
        } label: {
            ZStack {
                // Outer glow ring
                Circle()
                    .fill(DesignSystem.witnessRed.opacity(0.15))
                    .frame(width: glowSize, height: glowSize)
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
                    .frame(width: pulseRingSize, height: pulseRingSize)
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
                            endRadius: buttonSize / 2
                        )
                    )
                    .frame(width: buttonSize, height: buttonSize)
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
                            .font(.system(size: iconSize, weight: .medium))

                        Text("WITNESS")
                            .font(.system(size: textSize, weight: .heavy))
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
        guard !reduceMotion else { return }
        withAnimation(
            .easeInOut(duration: 2.5)
            .repeatForever(autoreverses: false)
        ) {
            pulseScale = 1.3
        }
    }

    private func startGlowAnimation() {
        guard !reduceMotion else { return }
        withAnimation(
            .easeInOut(duration: 2.0)
            .repeatForever(autoreverses: true)
        ) {
            glowIntensity = 0.6
        }
    }

    // ... (rest of method)

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
                        debugLog("[OnTheRecord] Live stream started: \(streamURLString ?? "none")")
                    } catch {
                        debugLog("[OnTheRecord] Live stream failed (continuing without): \(error)")
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
                debugLog("[OnTheRecord] Failed to start recording: \(error)")

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


// MARK: - No Backup Warning Banner

/// Persistent warning banner shown when no upload destinations are configured.
/// Tapping it opens Settings so the user can configure offsite backup.
struct NoBackupBanner: View {
    @Binding var showingSettings: Bool

    var body: some View {
        Button {
            showingSettings = true
        } label: {
            TintedGlassCard(tintColor: Colors.warningOrange, tintOpacity: 0.15, cornerRadius: Spacing.Radius.md, padding: Spacing.md) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(Colors.warningOrange)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("No Backup Destination")
                            .font(Typography.statusLabel)
                            .foregroundColor(.white)

                        Text("Recordings won't leave this device")
                            .font(Typography.caption)
                            .foregroundColor(.white.opacity(0.6))
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Spacing.screenPadding)
        .accessibilityLabel("No backup destination configured. Tap to open settings.")
        .accessibilityHint("Opens storage settings to configure offsite backup")
    }
}

struct ReadinessBar: View {
    @EnvironmentObject var alertService: AlertService

    private var hasContacts: Bool { !alertService.contacts.isEmpty }
    private var hasStorage: Bool { UserDefaults.standard.string(forKey: "nas_url") != nil }

    var body: some View {
        GlassCard(material: .regularMaterial, padding: Spacing.md) {
            HStack(spacing: Spacing.md) {
                // Pulse Dot
                Circle()
                    .fill(Colors.safeGreen)
                    .frame(width: 12, height: 12)
                    .glowEffect(color: Colors.safeGreen, intensity: 0.6)
                    .overlay(
                        Circle()
                            .stroke(Colors.safeGreen.opacity(0.5), lineWidth: 1)
                            .scaleEffect(1.4)
                            .opacity(0.5)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("SYSTEM ARMED")
                        .font(Typography.label)
                        .fontWeight(.black)
                        .foregroundColor(Colors.safeGreen)
                        .tracking(1.5)
                    
                    Text("Ready for immediate recording")
                        .font(Typography.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "shield.checkerboard")
                    .font(.system(size: 24))
                    .foregroundColor(Colors.safeGreen.opacity(0.8))
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.Radius.lg)
                .stroke(
                    LinearGradient(
                        colors: [Colors.safeGreen.opacity(0.3), Colors.safeGreen.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }
}

// MARK: - TacticalGrid (Shared Component)

struct TacticalGrid: View {
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let w = geometry.size.width
                let h = geometry.size.height
                
                // Rule of thirds
                path.move(to: CGPoint(x: w / 3, y: 0)); path.addLine(to: CGPoint(x: w / 3, y: h))
                path.move(to: CGPoint(x: 2 * w / 3, y: 0)); path.addLine(to: CGPoint(x: 2 * w / 3, y: h))
                path.move(to: CGPoint(x: 0, y: h / 3)); path.addLine(to: CGPoint(x: w, y: h / 3))
                path.move(to: CGPoint(x: 0, y: 2 * h / 3)); path.addLine(to: CGPoint(x: w, y: 2 * h / 3))
                
                // Corner Brackets
                // TL
                path.move(to: CGPoint(x: 20, y: 60)); path.addLine(to: CGPoint(x: 20, y: 20))
                path.addLine(to: CGPoint(x: 60, y: 20))
                // TR
                path.move(to: CGPoint(x: w - 60, y: 20)); path.addLine(to: CGPoint(x: w - 20, y: 20))
                path.addLine(to: CGPoint(x: w - 20, y: 60))
                // BL
                path.move(to: CGPoint(x: 20, y: h - 60)); path.addLine(to: CGPoint(x: 20, y: h - 20))
                path.addLine(to: CGPoint(x: 60, y: h - 20))
                // BR
                path.move(to: CGPoint(x: w - 60, y: h - 20)); path.addLine(to: CGPoint(x: w - 20, y: h - 20))
                path.addLine(to: CGPoint(x: w - 20, y: h - 60))
            }
            .stroke(Color.white.opacity(0.15), lineWidth: 1)
        }
    }
}

// MARK: - Retention Prompt View

struct RetentionPromptView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var historyService = IncidentHistoryService.shared

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: Spacing.md) {
                        // Header explanation
                        GlassCard(material: .thinMaterial, padding: Spacing.md) {
                            HStack(spacing: Spacing.sm) {
                                Image(systemName: "externaldrive.fill.badge.checkmark")
                                    .font(.system(size: 24))
                                    .foregroundColor(Colors.safeGreen)

                                Text("These older recordings have been safely uploaded. Free up space by removing local copies, or keep them.")
                                    .font(Typography.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.horizontal, Spacing.lg)

                        // Incident cards
                        ForEach(historyService.incidentsPendingReview) { incident in
                            GlassCard(material: .ultraThinMaterial, padding: Spacing.md) {
                                VStack(spacing: Spacing.sm) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(incident.id)
                                                .font(.system(.caption, design: .monospaced))
                                                .foregroundColor(.white)
                                            Text("\(incident.formattedDuration) • \(incident.formattedSize)")
                                                .font(Typography.caption)
                                                .foregroundColor(.white.opacity(0.6))
                                        }
                                        Spacer()
                                    }

                                    HStack(spacing: Spacing.sm) {
                                        Button {
                                            withAnimation { historyService.keepIncident(id: incident.id) }
                                        } label: {
                                            HStack(spacing: 4) {
                                                Image(systemName: "checkmark.circle.fill")
                                                Text("Keep")
                                            }
                                            .font(Typography.caption)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.white)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, Spacing.xs)
                                            .background(Colors.safeGreen.opacity(0.8), in: RoundedRectangle(cornerRadius: Spacing.Radius.sm))
                                        }

                                        Button {
                                            withAnimation { historyService.deleteIncidentData(id: incident.id) }
                                        } label: {
                                            HStack(spacing: 4) {
                                                Image(systemName: "trash.fill")
                                                Text("Delete")
                                            }
                                            .font(Typography.caption)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.white)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, Spacing.xs)
                                            .background(Colors.witnessRed.opacity(0.8), in: RoundedRectangle(cornerRadius: Spacing.Radius.sm))
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, Spacing.lg)
                        }

                        if historyService.incidentsPendingReview.isEmpty {
                            VStack(spacing: Spacing.sm) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 40))
                                    .foregroundColor(Colors.safeGreen)
                                Text("All clear")
                                    .font(Typography.bodyLarge)
                                    .foregroundColor(.white)
                                Text("No incidents pending review.")
                                    .font(Typography.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.top, Spacing.xl)
                        }
                    }
                    .padding(.top, Spacing.md)
                }
            }
            .navigationTitle("Manage Storage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
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

