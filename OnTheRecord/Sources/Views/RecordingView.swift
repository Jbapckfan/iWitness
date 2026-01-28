import SwiftUI
import AVFoundation

/// Minimal UI shown during active recording
/// Designed for high-stress situations with large touch targets
struct RecordingView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var recordingService: RecordingService
    @EnvironmentObject var uploadService: UploadService
    @EnvironmentObject var alertService: AlertService
    @EnvironmentObject var connectivityGuardian: ConnectivityGuardian
    @EnvironmentObject var liveStreamService: LiveStreamService

    @State private var showingSecurePhone = false
    @State private var screenFillOpacity: Double = 0.0
    private var stealthGestureEnabled: Bool { UserDefaults.standard.bool(forKey: "stealth_blackout_gesture") }

    var body: some View {
        ZStack {
            // LIVE CAMERA PREVIEW - Full screen background
            if recordingService.isDualCameraSupported {
                DualCameraPreviewView(recordingService: recordingService)
                    .ignoresSafeArea()
            } else {
                CameraPreviewView(recordingService: recordingService)
                    .ignoresSafeArea()
            }

            // Dark gradient overlay for readability
            LinearGradient(
                colors: [
                    Color.black.opacity(0.7),
                    Color.black.opacity(0.3),
                    Color.black.opacity(0.3),
                    Color.black.opacity(0.8)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Tactical HUD Overlay
            RecordingHUDOverlay()
                .ignoresSafeArea()

            // Screen Fill Light Overlay (Ring Light Style)
            if screenFillOpacity > 0 {
                GeometryReader { geometry in
                    let size = min(geometry.size.width, geometry.size.height)
                    let holeSize = size * 0.7 // 70% of screen width is clear
                    
                    Color.white
                        .opacity(screenFillOpacity * 0.95)
                        .mask(
                            ZStack {
                                Rectangle()
                                    .fill(Color.white)
                                
                                // Punch a hole in the center
                                Circle()
                                    .frame(width: holeSize, height: holeSize)
                                    .blendMode(.destinationOut)
                            }
                            .compositingGroup()
                        )
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }
            }
            
            // Stealth blackout overlay
            if appState.isBlackoutOn {
                Color.black
                    .ignoresSafeArea()
            }

            VStack(spacing: 0) {
                // Connectivity warning banner (if disconnected)
                if !connectivityGuardian.isConnected {
                    ConnectivityWarningBanner(secondsDisconnected: connectivityGuardian.secondsDisconnected)
                }

                // Recording indicator with large timer + camera flip (only for single cam)
                HStack {
                    Spacer()
                    RecordingHeader()
                    Spacer()
                }
                .overlay(alignment: .topLeading) {
                    // Secure Phone button
                    SecurePhoneButton(showingSheet: $showingSecurePhone)
                }
                .overlay(alignment: .topTrailing) {
                    HStack(spacing: Spacing.sm) {
                        // Light controls for night recording
                        LightControlPanel(screenFillOpacity: $screenFillOpacity)
                        
                        if !recordingService.isDualCameraSupported {
                            CameraFlipButton()
                        }
                    }
                }

                Spacer()

                // Minimal status overlay
                RecordingStatusOverlay()

                Spacer()

                // Action buttons - clear hierarchy
                ActionButtonsPanel()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .statusBar(hidden: true)
        .sheet(isPresented: $showingSecurePhone) {
            SecurePhoneSheet()
        }
        // Double-tap anywhere to toggle blackout when enabled
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            guard stealthGestureEnabled else { return }
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            withAnimation(.easeInOut(duration: 0.15)) {
                appState.isBlackoutOn.toggle()
            }
        })
    }
}

// MARK: - Connectivity Warning Banner

struct ConnectivityWarningBanner: View {
    let secondsDisconnected: Int

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 18, weight: .bold))

            VStack(alignment: .leading, spacing: 2) {
                Text("SIGNAL LOST")
                    .font(Typography.label)
                    .fontWeight(.black)
                Text("Offline for \(secondsDisconnected)s • Recording continues")
                    .font(.system(size: 11, weight: .medium))
                    .opacity(0.9)
            }

            Spacer()

            if secondsDisconnected > 30 {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.yellow)
            }
        }
        .foregroundColor(.white)
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Spacing.Radius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.Radius.sm)
                .stroke(Colors.errorRed.opacity(0.5), lineWidth: 1)
        )
        .background(
            RoundedRectangle(cornerRadius: Spacing.Radius.sm)
                .fill(Colors.errorRed.opacity(0.3))
        )
        .padding(.horizontal, Spacing.xxs)
        .padding(.top, Spacing.xs)
    }
}

// MARK: - Secure Phone Button

struct SecurePhoneButton: View {
    @Binding var showingSheet: Bool
    @EnvironmentObject var connectivityGuardian: ConnectivityGuardian

    var body: some View {
        GlassButton(title: "SECURE", icon: "lock.shield") {
            showingSheet = true
        }
        .padding(.top, Spacing.xs)
    }
}

// MARK: - Secure Phone Sheet

struct SecurePhoneSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var connectivityGuardian: ConnectivityGuardian

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.yellow)

                        Text("Secure Your Phone")
                            .font(.title.bold())

                        Text("Prevent forced unlock and tampering")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 8)

                    // Most important action
                    VStack(alignment: .leading, spacing: 12) {
                        Label("DISABLE \(connectivityGuardian.biometricType.uppercased()) NOW", systemImage: "faceid")
                            .font(.headline)
                            .foregroundColor(.red)

                        Text("Press and hold **Side + Volume** buttons for 2 seconds")
                            .font(.body)

                        Text("This shows the power off screen. Tap **Cancel**. \(connectivityGuardian.biometricType) is now disabled until you enter your passcode.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        // Visual guide
                        HStack(spacing: 20) {
                            VStack {
                                Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                                    .font(.system(size: 40))
                                Text("Hold buttons")
                                    .font(.caption2)
                            }

                            Image(systemName: "arrow.right")
                                .foregroundColor(.secondary)

                            VStack {
                                Image(systemName: "power")
                                    .font(.system(size: 40))
                                Text("See power off")
                                    .font(.caption2)
                            }

                            Image(systemName: "arrow.right")
                                .foregroundColor(.secondary)

                            VStack {
                                Image(systemName: "xmark.circle")
                                    .font(.system(size: 40))
                                Text("Tap Cancel")
                                    .font(.caption2)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(16)

                    // Other steps
                    ForEach(connectivityGuardian.securePhoneInstructions.dropFirst()) { step in
                        SecureStepRow(step: step)
                    }

                    // Shake to escalate info
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Shake to Escalate", systemImage: "hand.raised.fill")
                            .font(.headline)
                            .foregroundColor(.orange)

                        Text("If you're restrained and can't touch the screen, **shake your phone vigorously 3 times** to send an escalation alert to all contacts.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(16)

                    Spacer(minLength: 40)
                }
                .padding()
            }
            .navigationTitle("Security")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct SecureStepRow: View {
    let step: ConnectivityGuardian.SecureStep

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(step.number).")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Text(step.title)
                    .font(.headline)
            }

            Text(step.instruction)
                .font(.subheadline)

            Text(step.detail)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Dual Camera Preview (Picture-in-Picture style)

struct DualCameraPreviewView: View {
    let recordingService: RecordingService
    
    // State for draggable PiP position (corner: 0=topLeft, 1=topRight, 2=bottomLeft, 3=bottomRight)
    @State private var pipCorner: Int = 0
    @State private var dragOffset: CGSize = .zero
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Main camera (back camera - full screen)
                BackCameraLayer(recordingService: recordingService)
                    .ignoresSafeArea()
                
                // PiP camera (front camera - overlay)
                FrontCameraPiP(
                    recordingService: recordingService,
                    size: pipSize(for: geometry)
                )
                .offset(dragOffset)
                .position(pipPosition(for: geometry))
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            dragOffset = value.translation
                        }
                        .onEnded { value in
                            // Determine which corner to snap to
                            let currentPos = pipPosition(for: geometry)
                            let finalX = currentPos.x + value.translation.width
                            let finalY = currentPos.y + value.translation.height
                            
                            let centerX = geometry.size.width / 2
                            let centerY = geometry.size.height / 2
                            
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                if finalX > centerX && finalY > centerY {
                                    pipCorner = 3
                                } else if finalX > centerX {
                                    pipCorner = 1
                                } else if finalY > centerY {
                                    pipCorner = 2
                                } else {
                                    pipCorner = 0
                                }
                                dragOffset = .zero
                            }
                            
                            let generator = UIImpactFeedbackGenerator(style: .light)
                            generator.impactOccurred()
                        }
                )
            }
        }
    }
    
    private func pipSize(for geometry: GeometryProxy) -> CGSize {
        let width = geometry.size.width * 0.28
        let height = width * (4.0 / 3.0)
        return CGSize(width: width, height: height)
    }
    
    private func pipPosition(for geometry: GeometryProxy) -> CGPoint {
        let size = pipSize(for: geometry)
        let padding: CGFloat = 16
        let topPadding: CGFloat = 70
        let bottomPadding: CGFloat = 180
        
        switch pipCorner {
        case 0: return CGPoint(x: padding + size.width / 2, y: topPadding + size.height / 2)
        case 1: return CGPoint(x: geometry.size.width - padding - size.width / 2, y: topPadding + size.height / 2)
        case 2: return CGPoint(x: padding + size.width / 2, y: geometry.size.height - bottomPadding - size.height / 2)
        case 3: return CGPoint(x: geometry.size.width - padding - size.width / 2, y: geometry.size.height - bottomPadding - size.height / 2)
        default: return CGPoint(x: padding + size.width / 2, y: topPadding + size.height / 2)
        }
    }
}

// MARK: - Back Camera Layer (Main - Full Screen)

private struct BackCameraLayer: UIViewRepresentable {
    let recordingService: RecordingService
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .black
        
        if let layer = recordingService.backPreviewLayer {
            layer.videoGravity = .resizeAspectFill
            view.layer.addSublayer(layer)
        }
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        if let layer = recordingService.backPreviewLayer {
            layer.frame = uiView.bounds
        }
    }
}

// MARK: - Front Camera PiP with Visual Polish

private struct FrontCameraPiP: View {
    let recordingService: RecordingService
    let size: CGSize
    
    var body: some View {
        FrontCameraLayer(recordingService: recordingService)
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: Spacing.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.Radius.md)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.8), Color.white.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2.5
                    )
            )
            .shadow(color: .black.opacity(0.5), radius: 12, x: 0, y: 6)
            .shadow(color: Colors.safeGreen.opacity(0.15), radius: 20, x: 0, y: 0)
    }
}

// MARK: - Front Camera Layer (PiP)

private struct FrontCameraLayer: UIViewRepresentable {
    let recordingService: RecordingService
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .black
        view.clipsToBounds = true
        
        if let layer = recordingService.frontPreviewLayer {
            layer.videoGravity = .resizeAspectFill
            view.layer.addSublayer(layer)
        }
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        if let layer = recordingService.frontPreviewLayer {
            layer.frame = uiView.bounds
        }
    }
}

// MARK: - Camera Preview (UIKit Bridge) - Single Camera Fallback

struct CameraPreviewView: UIViewRepresentable {
    let recordingService: RecordingService

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .black

        if let previewLayer = recordingService.previewLayer {
            previewLayer.frame = UIScreen.main.bounds
            view.layer.addSublayer(previewLayer)
        }

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if let previewLayer = recordingService.previewLayer {
            previewLayer.frame = uiView.bounds
        }
    }
}

// MARK: - Camera Flip Button

struct CameraFlipButton: View {
    @EnvironmentObject var recordingService: RecordingService

    var body: some View {
        PremiumIconButton(icon: "camera.rotate.fill", size: 44, style: .glass) {
            recordingService.flipCamera()
        }
        .padding(.top, Spacing.xs)
    }
}

// MARK: - Recording Header (Large Timer)

struct RecordingHeader: View {
    @EnvironmentObject var appState: AppState
    @State private var isPulsing = false

    var body: some View {
        VStack(spacing: Spacing.md) {
            // Recording indicator with premium styling
            HStack(spacing: Spacing.sm) {
                PulsingIndicator(color: Colors.witnessRed, size: 14)

                Text("RECORDING")
                    .font(Typography.headline3)
                    .fontWeight(.heavy)
                    .foregroundColor(Colors.witnessRed)
                    .tracking(2)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xs)
            .glassBackground(cornerRadius: Spacing.Radius.full)

            // Large duration timer - primary focus with glow
            Text(appState.formattedDuration)
                .font(Typography.timerLarge)
                .foregroundColor(.white)
                .monospacedDigit()
                .shadow(color: Colors.witnessRed.opacity(0.3), radius: 10)
        }
        .padding(.vertical, Spacing.lg)
    }
}

// MARK: - Recording Status Overlay (Enhanced for production)

struct RecordingStatusOverlay: View {
    @EnvironmentObject var uploadService: UploadService
    @EnvironmentObject var recordingService: RecordingService
    @EnvironmentObject var liveStreamService: LiveStreamService
    @EnvironmentObject var alertService: AlertService
    @EnvironmentObject var appState: AppState

    @State private var showingShareSheet = false
    @State private var showingAddContact = false

    var body: some View {
        VStack(spacing: Spacing.sm) {
            // Camera status badges
            HStack(spacing: Spacing.sm) {
                CameraStatusBadge(
                    label: "FRONT",
                    isActive: true,
                    icon: "person.fill"
                )
                CameraStatusBadge(
                    label: "BACK",
                    isActive: recordingService.isDualCameraSupported,
                    icon: "video.fill"
                )
            }
            
            // Live Stream status (if active)
            if liveStreamService.isStreaming {
                LiveBadge(segmentCount: liveStreamService.segmentsUploaded) {
                    showingShareSheet = true
                }
                .sheet(isPresented: $showingShareSheet) {
                    ShareStreamSheet(streamURL: liveStreamService.streamURL)
                }
            }

            // Contacts notified status
            GlassCapsule {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.green)
                    
                    Text("\(alertService.alertsSent) contacts notified")
                        .font(Typography.caption)
                    
                    Divider()
                        .frame(height: 12)
                        .background(Color.white.opacity(0.3))
                    
                    // Quick add contact button
                    Button {
                        showingAddContact = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 14))
                            Text("Add")
                                .font(Typography.caption)
                        }
                        .foregroundColor(.yellow)
                    }
                }
                .foregroundColor(.white)
            }
            .sheet(isPresented: $showingAddContact) {
                QuickAddContactSheet()
            }

            // Backup status with queue depth
            GlassCapsule {
                HStack(spacing: Spacing.xs) {
                    if uploadService.isUploading {
                        ProgressView()
                            .scaleEffect(0.7)
                            .tint(.white)
                        Text("Uploading \(uploadService.queueDepth) chunks...")
                            .font(Typography.caption)
                    } else if uploadService.queueDepth > 0 {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.orange)
                        Text("\(uploadService.queueDepth) pending")
                            .font(Typography.caption)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(Colors.safeGreen)
                        Text("All backed up")
                            .font(Typography.caption)
                    }
                }
                .foregroundColor(.white)
            }

            // Segment counter
            Text("\(recordingService.currentChunkNumber) segments • \(uploadService.chunksUploaded) uploaded")
                .font(Typography.caption)
                .foregroundColor(.white.opacity(0.7))
        }
    }
}

// MARK: - Camera Status Badge

struct CameraStatusBadge: View {
    let label: String
    let isActive: Bool
    let icon: String
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(label)
                .font(.system(size: 10, weight: .bold))
        }
        .foregroundColor(isActive ? .white : .white.opacity(0.4))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(isActive ? Colors.safeGreen.opacity(0.8) : Color.gray.opacity(0.3))
        )
    }
}

// MARK: - Quick Add Contact Sheet (During Recording)

struct QuickAddContactSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var alertService: AlertService
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var liveStreamService: LiveStreamService
    
    @State private var name = ""
    @State private var phone = ""
    @State private var isSending = false
    @State private var sentSuccess = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("Phone", text: $phone)
                        .keyboardType(.phonePad)
                } header: {
                    Text("Add Contact & Alert Immediately")
                } footer: {
                    Text("This contact will receive an emergency alert with your location right now.")
                }
                
                Section {
                    Button {
                        addAndAlert()
                    } label: {
                        HStack {
                            if isSending {
                                ProgressView()
                                    .tint(.white)
                                Text("Sending Alert...")
                            } else if sentSuccess {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Alert Sent!")
                            } else {
                                Image(systemName: "bolt.fill")
                                Text("Add & Send Alert Now")
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .foregroundColor(.white)
                    }
                    .listRowBackground(
                        sentSuccess ? Colors.safeGreen : (name.isEmpty || phone.isEmpty ? Color.gray : Colors.witnessRed)
                    )
                    .disabled(name.isEmpty || phone.isEmpty || isSending)
                }
            }
            .navigationTitle("Quick Add Contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
    
    private func addAndAlert() {
        isSending = true
        
        // Add contact
        let contact = AlertService.EmergencyContact(
            name: name,
            phone: phone,
            email: nil,
            isLawyer: false,
            priority: alertService.contacts.count + 1
        )
        alertService.addContact(contact)
        
        // Send immediate alert
        Task {
            await alertService.sendEmergencyAlert(
                incidentID: appState.currentIncidentID ?? "UNKNOWN",
                location: nil,
                streamURL: liveStreamService.streamURL?.absoluteString
            )
            
            await MainActor.run {
                isSending = false
                sentSuccess = true
                
                // Haptic success
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
                
                // Auto-dismiss after short delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Share Stream Sheet

struct ShareStreamSheet: View {
    let streamURL: URL?
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 60))
                    .foregroundColor(.red)

                Text("Share Live Stream")
                    .font(.title2.bold())

                if let url = streamURL {
                    VStack(spacing: 8) {
                        Text(url.absoluteString)
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)

                        HStack(spacing: 16) {
                            Button {
                                UIPasteboard.general.string = url.absoluteString
                                let generator = UINotificationFeedbackGenerator()
                                generator.notificationOccurred(.success)
                            } label: {
                                Label("Copy Link", systemImage: "doc.on.doc")
                            }
                            .buttonStyle(.bordered)

                            ShareLink(item: url) {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                } else {
                    Text("Stream URL not available")
                        .foregroundColor(.secondary)
                }

                Text("Anyone with this link can watch your live stream")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()
            }
            .padding()
            .navigationTitle("Live Stream")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Light Control Panel (Flashlight + Screen Fill)

struct LightControlPanel: View {
    @EnvironmentObject var recordingService: RecordingService
    @Binding var screenFillOpacity: Double
    
    @State private var isExpanded = false
    @State private var torchLevel: Float = 0.0
    
    var body: some View {
        VStack(spacing: Spacing.sm) {
            // Toggle button
            Button {
                withAnimation(.spring(response: 0.3)) {
                    isExpanded.toggle()
                }
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
            } label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: isLightActive ? "flashlight.on.fill" : "flashlight.off.fill")
                        .font(.system(size: 18, weight: .semibold))
                    if isExpanded {
                        Text("LIGHTS")
                            .font(Typography.label)
                    }
                }
                .foregroundColor(isLightActive ? .yellow : .white)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(.ultraThinMaterial, in: Capsule())
            }
            
            // Expanded controls
            if isExpanded {
                VStack(spacing: Spacing.md) {
                    // Torch (Back Camera Flash)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "flashlight.on.fill")
                                .foregroundColor(.yellow)
                            Text("Flashlight")
                                .font(Typography.caption)
                            Spacer()
                            Text("\(Int(torchLevel * 100))%")
                                .font(Typography.caption)
                                .foregroundColor(.secondary)
                        }
                        Slider(value: Binding(
                            get: { Double(torchLevel) },
                            set: { newValue in
                                torchLevel = Float(newValue)
                                updateTorch()
                            }
                        ), in: 0...1)
                        .tint(.yellow)
                    }
                    
                    // Screen Fill Light (Front Camera)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "sun.max.fill")
                                .foregroundColor(.white)
                            Text("Screen Fill")
                                .font(Typography.caption)
                            Spacer()
                            Text("\(Int(screenFillOpacity * 100))%")
                                .font(Typography.caption)
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $screenFillOpacity, in: 0...1)
                            .tint(.white)
                            .onChange(of: screenFillOpacity) { _, newValue in
                                updateScreenBrightness()
                            }
                    }
                    
                    // Quick presets
                    HStack(spacing: Spacing.sm) {
                        PresetButton(title: "Off", isActive: torchLevel == 0 && screenFillOpacity == 0) {
                            withAnimation { torchLevel = 0; screenFillOpacity = 0 }
                            updateTorch()
                        }
                        PresetButton(title: "Low", isActive: false) {
                            withAnimation { torchLevel = 0.3; screenFillOpacity = 0.3 }
                            updateTorch()
                        }
                        PresetButton(title: "High", isActive: false) {
                            withAnimation { torchLevel = 1.0; screenFillOpacity = 0.8 }
                            updateTorch()
                        }
                    }
                }
                .padding(Spacing.md)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Spacing.Radius.md))
                .transition(.scale.combined(with: .opacity))
            }
        }
        .onDisappear {
            // Turn off lights when leaving
            torchLevel = 0
            screenFillOpacity = 0
            updateTorch()
        }
    }
    
    private var isLightActive: Bool {
        torchLevel > 0 || screenFillOpacity > 0
    }
    
    private func updateTorch() {
        guard let device = AVCaptureDevice.default(for: .video),
              device.hasTorch else { return }
        
        do {
            try device.lockForConfiguration()
            if torchLevel > 0 {
                try device.setTorchModeOn(level: torchLevel)
            } else {
                device.torchMode = .off
            }
            device.unlockForConfiguration()
        } catch {
            print("[OnTheRecord] Torch error: \(error)")
        }
    }
    
    private func updateScreenBrightness() {
        // Screen brightness is handled by the overlay in RecordingView
        // This just triggers an update
    }
}

struct PresetButton: View {
    let title: String
    let isActive: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Typography.caption)
                .foregroundColor(isActive ? .black : .white)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(isActive ? Color.yellow : Color.white.opacity(0.2))
                .clipShape(Capsule())
        }
    }
}

// MARK: - Screen Fill Light Overlay

struct ScreenFillLightOverlay: View {
    let opacity: Double
    
    var body: some View {
        if opacity > 0 {
            Color.white
                .opacity(opacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Action Buttons Panel

struct ActionButtonsPanel: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var recordingService: RecordingService
    @EnvironmentObject var alertService: AlertService
    @EnvironmentObject var liveStreamService: LiveStreamService

    @State private var safeButtonOffset: CGFloat = 0
    @State private var isEndingRecording = false

    var body: some View {
        VStack(spacing: Spacing.md) {
            // I'M SAFE - Primary action with PIN dial
            SafeButton(
                isProcessing: $isEndingRecording,
                action: endRecordingSafe
            )

            // NEED HELP - Secondary action with premium styling
            PremiumSecondaryButton(
                title: "NEED HELP",
                subtitle: "Send escalation alert, keep recording",
                icon: "exclamationmark.triangle.fill",
                color: Colors.warningOrange
            ) {
                requestHelp()
            }
        }
    }

    private func endRecordingSafe() {
        isEndingRecording = true

        // Haptic
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()

        Task {
            // Stop recording (saves to Photos + finalizes NAS upload)
            await recordingService.stopRecording()

            // Stop live stream if active
            if liveStreamService.isStreaming {
                await liveStreamService.stopStream()
            }

            // End Live Activity (Dynamic Island)
            LiveActivityManager.shared.end()

            // Notify contacts that user is safe
            await alertService.sendSafeSignal()
            appState.markSafe()

            // Success haptic
            let successGenerator = UINotificationFeedbackGenerator()
            successGenerator.notificationOccurred(.success)

            // Wait for uploads to complete
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            appState.reset()
        }
    }

    private func requestHelp() {
        // Escalate alerts
        Task {
            if let incidentID = appState.currentIncidentID {
                await alertService.escalateAlert(incidentID: incidentID)
            }
        }

        // Haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
    }
}

// MARK: - Safe Button with Radial PIN Dial

struct SafeButton: View {
    @Binding var isProcessing: Bool
    let action: () -> Void

    @EnvironmentObject var appState: AppState
    @EnvironmentObject var alertService: AlertService

    @State private var showingDial = false
    @State private var showingSetup = false
    @State private var enteredDigits: [Int] = []
    @State private var currentTarget: Int? = nil
    @State private var isAtCenter = true
    @State private var dragLocation: CGPoint = .zero
    @State private var shakeOffset: CGFloat = 0
    @State private var failedAttempts = 0

    private let dialSize: CGFloat = 280
    private let centerRadius: CGFloat = 50
    private let digitRadius: CGFloat = 110
    private let requiredDigits = 4

    // Get stored PIN if configured
    private var storedPIN: [Int]? {
        guard let pinString = UserDefaults.standard.string(forKey: "safe_pin"), !pinString.isEmpty else { return nil }
        return pinString.compactMap { Int(String($0)) }
    }

    // Optional duress PIN
    private var duressPIN: [Int]? {
        guard let pinString = UserDefaults.standard.string(forKey: "duress_pin"), !pinString.isEmpty else { return nil }
        return pinString.compactMap { Int(String($0)) }
    }

    var body: some View {
        ZStack {
            if showingDial {
                // Fullscreen overlay for dial
                Color.black.opacity(0.9)
                    .ignoresSafeArea()
                    .onTapGesture {
                        // Cancel on tap outside
                        withAnimation(.spring(response: 0.3)) {
                            showingDial = false
                            resetDial()
                        }
                    }

                // Radial dial
                RadialDial(
                    enteredDigits: $enteredDigits,
                    currentTarget: $currentTarget,
                    isAtCenter: $isAtCenter,
                    onDigitEntered: handleDigitEntered,
                    onComplete: handlePINComplete,
                    onCancel: {
                        withAnimation(.spring(response: 0.3)) {
                            showingDial = false
                            resetDial()
                        }
                    },
                    dialSize: dialSize,
                    centerRadius: centerRadius,
                    digitRadius: digitRadius,
                    requiredDigits: requiredDigits
                )
                .offset(x: shakeOffset)
            } else {
                // Initial button with premium styling
                Button {
                    // Require Safe PIN to be set before showing dial
                    guard storedPIN != nil else {
                        showingSetup = true
                        return
                    }
                    withAnimation(AnimationPresets.entrance) { showingDial = true }
                    let generator = UIImpactFeedbackGenerator(style: .medium); generator.impactOccurred()
                } label: {
                    HStack(spacing: Spacing.md) {
                        if isProcessing {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(1.2)
                        } else {
                            Image(systemName: "checkmark.shield.fill")
                                .font(.system(size: 28, weight: .semibold))
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(isProcessing ? "ENDING..." : "I'M SAFE")
                                .font(Typography.headline3)
                            if !isProcessing {
                                Text("Hold & enter PIN to confirm")
                                    .font(Typography.caption)
                                    .opacity(0.9)
                            }
                        }

                        Spacer()

                        if !isProcessing {
                            Image(systemName: "dial.medium.fill")
                                .font(.system(size: 20, weight: .bold))
                                .opacity(0.7)
                        }
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, Spacing.lg)
                    .frame(height: 72)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: Spacing.Radius.lg)
                            .fill(Colors.safeGreen)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Spacing.Radius.lg)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .shadow(color: Colors.safeGreen.opacity(0.5), radius: 12, y: 4)
                }
                .disabled(isProcessing)
            }
        }
        .frame(height: 72)
        .sheet(isPresented: $showingSetup) {
            SafePINSetupView()
        }
    }

    private func handleDigitEntered(_ digit: Int) {
        enteredDigits.append(digit)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    private func handlePINComplete() {
        if let sp = storedPIN, enteredDigits == sp {
            // Correct PIN!
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            withAnimation(.spring(response: 0.3)) {
                showingDial = false
                isProcessing = true
            }
            resetDial()
            action()
        } else {
            // Wrong PIN
            failedAttempts += 1
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)

            // Shake animation
            withAnimation(.spring(response: 0.1, dampingFraction: 0.3)) {
                shakeOffset = 20
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.1, dampingFraction: 0.3)) {
                    shakeOffset = -20
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(.spring(response: 0.1, dampingFraction: 0.3)) {
                    shakeOffset = 0
                }
            }

            // Reset for retry
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                resetDial()
            }

            // Duress PIN match triggers silent escalation
            if let dPIN = duressPIN, enteredDigits == dPIN {
                Task {
                    if let incidentID = appState.currentIncidentID {
                        await alertService.escalateAlert(incidentID: incidentID)
                    }
                }
                withAnimation(.spring(response: 0.3)) {
                    showingDial = false
                }
                resetDial()
                return
            }

            // After 3 failures, trigger silent duress escalation
            if failedAttempts >= 3 {
                Task {
                    if let incidentID = appState.currentIncidentID {
                        await alertService.escalateAlert(incidentID: incidentID)
                    }
                }
            }
        }
    }

    private func resetDial() {
        enteredDigits = []
        currentTarget = nil
        isAtCenter = true
    }
}

// MARK: - Radial Dial Component

struct RadialDial: View {
    @Binding var enteredDigits: [Int]
    @Binding var currentTarget: Int?
    @Binding var isAtCenter: Bool

    let onDigitEntered: (Int) -> Void
    let onComplete: () -> Void
    let onCancel: () -> Void

    let dialSize: CGFloat
    let centerRadius: CGFloat
    let digitRadius: CGFloat
    let requiredDigits: Int

    @State private var dragLocation: CGPoint? = nil

    // Digits arranged clockwise from top: 0 at top, then 1-9
    private let digits = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]

    var body: some View {
        VStack(spacing: 24) {
            // Progress dots
            HStack(spacing: 12) {
                ForEach(0..<requiredDigits, id: \.self) { index in
                    Circle()
                        .fill(index < enteredDigits.count ? DesignSystem.safeGreen : Color.white.opacity(0.3))
                        .frame(width: 16, height: 16)
                        .scaleEffect(index < enteredDigits.count ? 1.2 : 1.0)
                        .animation(.spring(response: 0.2), value: enteredDigits.count)
                }
            }

            Text("Drag to each digit, return to center")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.6))

            // The dial
            ZStack {
                // Outer ring
                Circle()
                    .stroke(Color.white.opacity(0.2), lineWidth: 2)
                    .frame(width: dialSize, height: dialSize)

                // Digit circles
                ForEach(digits, id: \.self) { digit in
                    let angle = angleForDigit(digit)
                    let position = positionForAngle(angle, radius: digitRadius)

                    ZStack {
                        Circle()
                            .fill(currentTarget == digit ? DesignSystem.safeGreen : Color.white.opacity(0.15))
                            .frame(width: 52, height: 52)

                        Text("\(digit)")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(currentTarget == digit ? .white : .white.opacity(0.8))
                    }
                    .scaleEffect(currentTarget == digit ? 1.15 : 1.0)
                    .offset(x: position.x, y: position.y)
                    .animation(.spring(response: 0.2), value: currentTarget)
                }

                // Center return zone
                ZStack {
                    Circle()
                        .fill(isAtCenter ? DesignSystem.safeGreen.opacity(0.8) : Color.white.opacity(0.2))
                        .frame(width: centerRadius * 2, height: centerRadius * 2)

                    if enteredDigits.isEmpty {
                        Text("START")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    } else {
                        Image(systemName: "checkmark")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .scaleEffect(isAtCenter ? 1.1 : 1.0)
                .animation(.spring(response: 0.2), value: isAtCenter)

                // Drag line indicator
                if let drag = dragLocation, !isAtCenter {
                    Path { path in
                        path.move(to: CGPoint(x: dialSize/2, y: dialSize/2))
                        path.addLine(to: drag)
                    }
                    .stroke(DesignSystem.safeGreen.opacity(0.5), lineWidth: 3)
                }
            }
            .frame(width: dialSize, height: dialSize)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let center = CGPoint(x: dialSize/2, y: dialSize/2)
                        let location = value.location
                        dragLocation = location

                        let dx = location.x - center.x
                        let dy = location.y - center.y
                        let distance = sqrt(dx*dx + dy*dy)

                        if distance < centerRadius {
                            // At center
                            if !isAtCenter && currentTarget != nil {
                                // Just returned to center after selecting a digit
                                if let target = currentTarget {
                                    onDigitEntered(target)
                                }
                                currentTarget = nil
                            }
                            isAtCenter = true
                            
                            // Check completion AFTER setting isAtCenter
                            // This ensures we only trigger once per digit entry
                            if enteredDigits.count >= requiredDigits {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                    onComplete()
                                }
                            }
                        } else {
                            // Outside center - find nearest digit
                            isAtCenter = false
                            let angle = atan2(dy, dx)
                            currentTarget = digitForAngle(angle)
                        }
                    }
                    .onEnded { _ in
                        dragLocation = nil
                        // If ended outside center, reset
                        if !isAtCenter {
                            currentTarget = nil
                            isAtCenter = true
                        }
                    }
            )

            // Cancel button
            Button {
                onCancel()
            } label: {
                Text("Cancel")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.horizontal, 32)
                    .padding(.vertical, 12)
            }
        }
    }

    private func angleForDigit(_ digit: Int) -> Double {
        // 0 at top (-90°), then clockwise
        let baseAngle = -Double.pi / 2 // Start at top
        let step = (2 * Double.pi) / 10 // 36° per digit
        return baseAngle + Double(digit) * step
    }

    private func positionForAngle(_ angle: Double, radius: CGFloat) -> CGPoint {
        CGPoint(
            x: cos(angle) * radius,
            y: sin(angle) * radius
        )
    }

    private func digitForAngle(_ angle: Double) -> Int {
        // Convert angle to digit (0 at top, clockwise)
        var normalized = angle + Double.pi / 2 // Shift so 0 is at top
        if normalized < 0 { normalized += 2 * Double.pi }
        let step = (2 * Double.pi) / 10
        let digit = Int(round(normalized / step)) % 10
        return digit
    }
}

#Preview {
    RecordingView()
        .environmentObject(AppState())
        .environmentObject(RecordingService())
        .environmentObject(UploadService())
        .environmentObject(AlertService())
}
