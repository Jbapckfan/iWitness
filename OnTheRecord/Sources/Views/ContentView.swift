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

// MARK: - Home View (Tactical Terminal)

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
    
    // Scrolling diag text
    @State private var diagLog: [String] = []
    let timer = Timer.publish(every: 2.0, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ZStack {
                // Background: Deep Black with Grid
                Color.black.ignoresSafeArea()
                TacticalGrid().opacity(0.3)
                
                VStack(spacing: 0) {
                    // Header: System Identity
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("ON_THE_RECORD // V2.0")
                                .font(Typography.terminalBold)
                                .foregroundColor(Colors.witnessRed)
                            Text("SECURE_ENCLAVE: ACTIVE")
                                .font(Typography.terminalLog)
                                .foregroundColor(.gray)
                        }
                        .accessibilityLabel("OnTheRecord version 2.0")
                        Spacer()
                        
                        // Settings / Info Gear
                        HStack(spacing: 20) {
                            Button { showingOnboarding = true } label: {
                                Image(systemName: "questionmark.square.dashed")
                                    .font(.system(size: 20))
                            }
                            .accessibilityLabel("Help")
                            Button { showingSettings = true } label: {
                                Image(systemName: "gearshape.fill")
                                    .font(.system(size: 20))
                            }
                            .accessibilityLabel("Settings")
                        }
                        .foregroundColor(.white)
                    }
                    .padding()
                    .background(Colors.glassDark)
                    .fadeScaleEntrance(isPresented: isViewAppeared)

                    // Main Terminal Display
                    ScrollView {
                        VStack(spacing: Spacing.lg) {

                            // 1. Diagnostics Log (Aesthetic)
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(diagLog.suffix(5), id: \.self) { log in
                                    Text("> \(log)")
                                        .font(Typography.terminalLog)
                                        .foregroundColor(Colors.safeGreen.opacity(0.7))
                                        .transition(.opacity)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Color.black.opacity(0.5))
                            .border(Colors.safeGreen.opacity(0.2), width: 1)
                            .padding(.horizontal)
                            .slideUpEntrance(isPresented: isViewAppeared, delay: 0.1)
                            
                            // 1.5 No-backup warning (persistent until configured)
                            if uploadService.destinations.isEmpty {
                                NoBackupBanner(showingSettings: $showingSettings)
                                    .slideUpEntrance(isPresented: isViewAppeared, delay: 0.15)
                            }

                            // 2. Critical Status check
                            VStack(spacing: Spacing.sm) {
                                SystemCheckRow(label: "CONTACTS_LINK", status: !alertService.contacts.isEmpty)
                                    .staggeredEntrance(isPresented: isViewAppeared, index: 0)
                                SystemCheckRow(label: "OFFSHORE_UPLINK", status: UserDefaults.standard.string(forKey: "nas_url") != nil)
                                    .staggeredEntrance(isPresented: isViewAppeared, index: 1)
                                SystemCheckRow(label: "CAMERA_MATRIX", status: true)
                                    .staggeredEntrance(isPresented: isViewAppeared, index: 2)
                            }
                            .padding(.horizontal)
                            
                            Spacer(minLength: 40)
                            
                            // 3. Activation Core
                            ZStack {
                                // Industrial Ring
                                Circle()
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 2)
                                    .frame(width: 260, height: 260)
                                
                                // Dashed Ring
                                if !reduceMotion {
                                    Circle()
                                        .stroke(Color.white.opacity(0.1), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
                                        .frame(width: 290, height: 290)
                                        .rotationEffect(.degrees(isViewAppeared ? 360 : 0))
                                        .animation(.linear(duration: 20).repeatForever(autoreverses: false), value: isViewAppeared)
                                }
                                
                                ActivationButton()
                            }
                            
                            Text("SYSTEM_ARMED // READY_TO_ENGAGE")
                                .font(Typography.terminalSmall)
                                .foregroundColor(Colors.safeGreen)
                                .tracking(2)
                                .padding(.top, Spacing.screenPadding)
                                .fadeScaleEntrance(isPresented: isViewAppeared, delay: 0.3)
                            
                        }
                        .padding(.vertical)
                    }
                }
            }
            .navigationBarHidden(true)
            .onAppear {
                isViewAppeared = true
                addLog("INIT_SYSTEM_CORE")
            }
            .onReceive(timer) { _ in
                 addRandomLog()
            }
        }
    }
    
    private func addLog(_ text: String) {
        withAnimation {
            diagLog.append(text)
            if diagLog.count > 10 { diagLog.removeFirst() }
        }
    }
    
    private func addRandomLog() {
        let logs = [
            "CHECK_MEM_INTEGRITY... OK",
            "PING_OFFSHORE... 24ms",
            "ENCR_KEYS_VERIFIED",
            "AUDIO_SUB_SYSTEM... READY",
            "GPS_TRIANGULATION... ACQUIRED",
            "OPTICAL_SENSORS... CALIBRATED"
        ]
        addLog(logs.randomElement()!)
    }
}

// MARK: - Components

struct SystemCheckRow: View {
    let label: String
    let status: Bool
    
    var body: some View {
        HStack {
            Text(label)
                .font(Typography.terminalBody)
                .foregroundColor(.white)
            
            Spacer()
            
            Text(status ? "[ONLINE]" : "[OFFLINE]")
                .font(Typography.terminalBold)
                .foregroundColor(status ? Colors.safeGreen : Colors.errorRed)
        }
        .padding(Spacing.sm)
        .background(Color.white.opacity(0.05))
        .border(status ? Colors.safeGreen.opacity(0.3) : Colors.errorRed.opacity(0.3), width: 1)
        .accessibilityLabel("\(label): \(status ? "online" : "offline")")
    }
}

// Re-using TacticalGrid from HUD


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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            HStack(spacing: Spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.black.opacity(0.85))

                VStack(alignment: .leading, spacing: 2) {
                    Text("NO BACKUP DESTINATION")
                        .font(Typography.label)
                        .fontWeight(.black)
                        .tracking(1)
                        .foregroundColor(.black.opacity(0.9))

                    Text("Recordings won't leave this device")
                        .font(Typography.caption)
                        .foregroundColor(.black.opacity(0.7))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.black.opacity(0.5))
            }
            .padding(Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Spacing.Radius.md)
                    .fill(Colors.warningOrange)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.Radius.md)
                    .stroke(Colors.warningOrange.opacity(0.6), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
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
            List {
                Section {
                    Text("These older recordings have been safely uploaded. You can free up space by removing local copies, or keep them.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                ForEach(historyService.incidentsPendingReview) { incident in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(incident.id)
                                .font(.system(.caption, design: .monospaced))
                            Text("\(incident.formattedDuration) • \(incident.formattedSize)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Button("Keep") {
                            historyService.keepIncident(id: incident.id)
                        }
                        .buttonStyle(.bordered)
                        .tint(.green)

                        Button("Delete") {
                            historyService.deleteIncidentData(id: incident.id)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                }
            }
            .navigationTitle("Manage Storage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
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

