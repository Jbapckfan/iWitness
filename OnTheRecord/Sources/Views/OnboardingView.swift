import SwiftUI
import AVFoundation
import CoreLocation
import UserNotifications

// MARK: - Location Manager Helper

class LocationManagerHelper: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    var authorizationStatus: CLAuthorizationStatus {
        manager.authorizationStatus
    }

    override init() {
        super.init()
        manager.delegate = self
    }

    func requestWhenInUseAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        objectWillChange.send()
    }
}

// MARK: - Onboarding View

struct OnboardingView: View {
    @Environment(\.dismiss) var dismiss
    @State private var currentPage = 0

    var body: some View {
        ZStack {
            // Premium ambient background
            AnimatedGradientBackground(colors: [
                Color(white: 0.03),
                Color(white: 0.08),
                Color(white: 0.03)
            ], animationDuration: 10)

            TabView(selection: $currentPage) {
                WelcomePage()
                    .tag(0)

                PermissionsPage()
                    .tag(1)

                ContactsSetupPage()
                    .tag(2)

                StorageSetupPage()
                    .tag(3)

                SafePINOnboardingPage(currentPage: $currentPage, nextTag: 5)
                    .tag(4)

                SecurityDrillPage()
                    .tag(5)

                InvitePage()
                    .tag(6)

                CompletePage(dismiss: dismiss)
                    .tag(7)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
        }
    }
}

// MARK: - Welcome Page

struct WelcomePage: View {
    @State private var isAppeared = false
    @State private var iconScale: CGFloat = 0.5

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            // Animated icon with glow
            ZStack {
                Circle()
                    .fill(Colors.witnessRed.opacity(0.2))
                    .frame(width: 120, height: 120)
                    .blur(radius: 30)

                Image(systemName: "video.badge.checkmark")
                    .font(.system(size: 80))
                    .foregroundColor(Colors.witnessRed)
                    .scaleEffect(iconScale)
            }
            .onAppear {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.6)) {
                    iconScale = 1.0
                }
            }

            VStack(spacing: Spacing.xs) {
                Text("Welcome to OnTheRecord")
                    .font(Typography.displayMedium)
                    .foregroundColor(.white)

                Text("Document what matters.\nProtect what's important.")
                    .font(Typography.bodyLarge)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
            }
            .fadeScaleEntrance(isPresented: isAppeared, delay: 0.2)

            Spacer()

            GlassCard(material: .ultraThinMaterial, padding: Spacing.md) {
                VStack(spacing: Spacing.sm) {
                    ForEach(Array(features.enumerated()), id: \.offset) { index, feature in
                        FeatureRow(icon: feature.icon, text: feature.text)
                            .staggeredEntrance(isPresented: isAppeared, index: index)
                    }
                }
            }
            .padding(.horizontal, Spacing.md)

            Spacer()

            Text("Swipe to continue →")
                .font(Typography.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isAppeared = true
            }
        }
    }

    private var features: [(icon: String, text: String)] {
        [
            ("video.fill", "Dual-camera recording"),
            ("lock.shield.fill", "Encrypted cloud backup"),
            ("bell.fill", "Instant emergency alerts"),
            ("person.2.fill", "Community witness network")
        ]
    }
}

struct FeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Colors.witnessRed)
                .frame(width: 30)
            Text(text)
                .font(Typography.bodyMedium)
                .foregroundColor(.white)
            Spacer()
        }
    }
}

// MARK: - Permissions Page

struct PermissionsPage: View {
    @State private var cameraGranted = false
    @State private var microphoneGranted = false
    @State private var locationGranted = false
    @State private var notificationsGranted = false
    @State private var isAppeared = false
    @StateObject private var locationManager = LocationManagerHelper()

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Colors.safeGreen.opacity(0.2))
                    .frame(width: 100, height: 100)
                    .blur(radius: 25)

                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 60))
                    .foregroundColor(Colors.safeGreen)
            }

            VStack(spacing: Spacing.xs) {
                Text("Permissions")
                    .font(Typography.headline1)
                    .foregroundColor(.white)

                Text("OnTheRecord needs these permissions to protect you")
                    .font(Typography.bodyMedium)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
            }

            VStack(spacing: Spacing.sm) {
                PermissionButton(
                    icon: "camera.fill",
                    title: "Camera",
                    description: "Record video from both cameras",
                    isGranted: cameraGranted
                ) {
                    Task { cameraGranted = await requestCamera() }
                }
                .staggeredEntrance(isPresented: isAppeared, index: 0)

                PermissionButton(
                    icon: "mic.fill",
                    title: "Microphone",
                    description: "Capture audio evidence",
                    isGranted: microphoneGranted
                ) {
                    Task { microphoneGranted = await requestMicrophone() }
                }
                .staggeredEntrance(isPresented: isAppeared, index: 1)

                PermissionButton(
                    icon: "location.fill",
                    title: "Location",
                    description: "Share your location with contacts",
                    isGranted: locationGranted
                ) {
                    requestLocation()
                    locationGranted = true
                }
                .staggeredEntrance(isPresented: isAppeared, index: 2)

                PermissionButton(
                    icon: "bell.fill",
                    title: "Notifications",
                    description: "Receive community alerts",
                    isGranted: notificationsGranted
                ) {
                    Task { notificationsGranted = await requestNotifications() }
                }
                .staggeredEntrance(isPresented: isAppeared, index: 3)
            }
            .padding(.horizontal)

            Spacer()
        }
        .padding()
        .onAppear {
            checkExistingPermissions()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                isAppeared = true
            }
        }
    }

    private func checkExistingPermissions() {
        cameraGranted = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let status = locationManager.authorizationStatus
        locationGranted = status == .authorizedWhenInUse || status == .authorizedAlways
    }

    private func requestCamera() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    private func requestMicrophone() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    private func requestLocation() {
        locationManager.requestWhenInUseAuthorization()
    }

    private func requestNotifications() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }
}

struct PermissionButton: View {
    let icon: String
    let title: String
    let description: String
    let isGranted: Bool
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(isGranted ? Colors.safeGreen : .white)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Typography.bodyLarge)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    Text(description)
                        .font(Typography.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isGranted {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(Colors.safeGreen)
                } else {
                    Text("Enable")
                        .font(Typography.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xxs + 2)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(Spacing.Radius.xs)
                }
            }
            .padding(Spacing.md)
            .glassBackground(cornerRadius: Spacing.Radius.md)
            .scaleEffect(isPressed ? 0.98 : 1.0)
        }
        .buttonStyle(PremiumPressStyle(isPressed: $isPressed))
        .disabled(isGranted)
    }
}

// MARK: - Contacts Setup Page

struct ContactsSetupPage: View {
    @EnvironmentObject var alertService: AlertService
    @State private var showingAddContact = false
    @State private var isAppeared = false

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 100, height: 100)
                    .blur(radius: 25)

                Image(systemName: "person.2.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
            }
            .fadeScaleEntrance(isPresented: isAppeared)

            VStack(spacing: Spacing.xs) {
                Text("Emergency Contacts")
                    .font(Typography.headline1)
                    .foregroundColor(.white)

                Text("Who should be notified when you activate Witness mode?")
                    .font(Typography.bodyMedium)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
            }
            .slideUpEntrance(isPresented: isAppeared, delay: 0.1)

            if alertService.contacts.isEmpty {
                VStack(spacing: Spacing.sm) {
                    Text("No contacts added yet")
                        .font(Typography.bodyMedium)
                        .foregroundColor(.secondary)

                    PremiumPrimaryButton(
                        title: "Add Contact",
                        icon: "person.badge.plus",
                        color: .blue
                    ) {
                        showingAddContact = true
                    }
                }
                .staggeredEntrance(isPresented: isAppeared, index: 2)
            } else {
                VStack(spacing: Spacing.xs) {
                    ForEach(Array(alertService.contacts.enumerated()), id: \.element.id) { index, contact in
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "person.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.white.opacity(0.8))
                            Text(contact.name)
                                .font(Typography.bodyMedium)
                                .foregroundColor(.white)
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(Colors.safeGreen)
                        }
                        .padding(Spacing.md)
                        .glassBackground(cornerRadius: Spacing.Radius.sm)
                        .staggeredEntrance(isPresented: isAppeared, index: index + 2)
                    }

                    GlassButton(title: "Add Another", icon: "plus") {
                        showingAddContact = true
                    }
                    .staggeredEntrance(isPresented: isAppeared, index: alertService.contacts.count + 2)
                }
                .padding(.horizontal, Spacing.md)
            }

            Spacer()

            Text("You can add more contacts later in Settings")
                .font(Typography.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .sheet(isPresented: $showingAddContact) {
            AddContactView()
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                isAppeared = true
            }
        }
    }
}

// MARK: - Storage Setup Page

struct StorageSetupPage: View {
    @State private var showingNASSetup = false
    @State private var hasNASConfigured = false
    @State private var isAppeared = false

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.2))
                    .frame(width: 100, height: 100)
                    .blur(radius: 25)

                Image(systemName: "externaldrive.badge.checkmark")
                    .font(.system(size: 60))
                    .foregroundColor(.orange)
            }
            .fadeScaleEntrance(isPresented: isAppeared)

            VStack(spacing: Spacing.xs) {
                Text("Backup Storage")
                    .font(Typography.headline1)
                    .foregroundColor(.white)

                Text("Where should your footage be stored?")
                    .font(Typography.bodyMedium)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
            }
            .slideUpEntrance(isPresented: isAppeared, delay: 0.1)

            VStack(spacing: Spacing.md) {
                StorageOption(
                    icon: "externaldrive.fill",
                    title: "Offsite Backup",
                    description: "Your home server or NAS",
                    isConfigured: hasNASConfigured
                ) {
                    showingNASSetup = true
                }
                .staggeredEntrance(isPresented: isAppeared, index: 2)

                StorageOption(
                    icon: "cloud.fill",
                    title: "Cloud Backup",
                    description: "Cloudflare R2 (coming soon)",
                    isConfigured: false,
                    isDisabled: true
                ) {
                    // Coming soon
                }
                .staggeredEntrance(isPresented: isAppeared, index: 3)
            }
            .padding(.horizontal, Spacing.md)

            Spacer()

            HStack(spacing: Spacing.xs) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 12))
                Text("Footage is encrypted before upload")
                    .font(Typography.caption)
            }
            .foregroundColor(.secondary)
        }
        .padding()
        .sheet(isPresented: $showingNASSetup) {
            NASSetupView()
        }
        .onAppear {
            hasNASConfigured = UserDefaults.standard.string(forKey: "nas_url") != nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                isAppeared = true
            }
        }
    }
}

struct StorageOption: View {
    let icon: String
    let title: String
    let description: String
    let isConfigured: Bool
    var isDisabled: Bool = false
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(isConfigured ? Colors.safeGreen : .white.opacity(0.9))
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Typography.bodyLarge)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    Text(description)
                        .font(Typography.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isConfigured {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(Colors.safeGreen)
                } else if !isDisabled {
                    Text("Setup")
                        .font(Typography.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xxs + 2)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(Spacing.Radius.xs)
                }
            }
            .padding(Spacing.md)
            .glassBackground(cornerRadius: Spacing.Radius.md)
            .opacity(isDisabled ? 0.5 : 1)
            .scaleEffect(isPressed ? 0.98 : 1.0)
        }
        .buttonStyle(PremiumPressStyle(isPressed: $isPressed))
        .disabled(isDisabled || isConfigured)
    }
}

// MARK: - Security Drill Page

struct SecurityDrillPage: View {
    @State private var hasCompletedDrill = false
    @State private var isAppeared = false

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.yellow.opacity(0.2))
                    .frame(width: 100, height: 100)
                    .blur(radius: 25)

                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.yellow)
            }
            .fadeScaleEntrance(isPresented: isAppeared)

            VStack(spacing: Spacing.xs) {
                Text("Security Drill")
                    .font(Typography.headline1)
                    .foregroundColor(.white)

                Text("Practice securing your phone quickly")
                    .font(Typography.bodyMedium)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
            }
            .slideUpEntrance(isPresented: isAppeared, delay: 0.1)

            GlassCard(material: .ultraThinMaterial, padding: Spacing.md) {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    ForEach(Array(drillSteps.enumerated()), id: \.offset) { index, step in
                        DrillStep(number: index + 1, text: step)
                            .staggeredEntrance(isPresented: isAppeared, index: index + 2)
                    }
                }
            }
            .padding(.horizontal, Spacing.md)

            if hasCompletedDrill {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Colors.safeGreen)
                    Text("Practice completed!")
                        .font(Typography.bodyMedium)
                        .foregroundColor(Colors.safeGreen)
                }
                .padding(Spacing.md)
                .glassBackground(cornerRadius: Spacing.Radius.md)
            } else {
                PremiumPrimaryButton(
                    title: "I've Practiced This",
                    icon: "checkmark.shield",
                    color: .yellow
                ) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        hasCompletedDrill = true
                    }
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                }
            }

            Spacer()

            HStack(spacing: Spacing.xs) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 12))
                Text("This ensures only your PIN can unlock your phone")
                    .font(Typography.caption)
            }
            .foregroundColor(.secondary)
        }
        .padding()
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                isAppeared = true
            }
        }
    }

    private var drillSteps: [String] {
        [
            "Hold SIDE + VOLUME buttons",
            "Wait for power-off screen",
            "Press CANCEL",
            "Face ID is now disabled!"
        ]
    }
}

struct DrillStep: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Text("\(number)")
                .font(Typography.bodyMedium)
                .fontWeight(.bold)
                .foregroundColor(.black)
                .frame(width: 28, height: 28)
                .background(Color.yellow)
                .clipShape(Circle())

            Text(text)
                .font(Typography.bodyMedium)
                .foregroundColor(.white)
        }
    }
}

// MARK: - Complete Page

struct CompletePage: View {
    let dismiss: DismissAction
    @State private var isAppeared = false
    @State private var iconScale: CGFloat = 0.5

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Colors.safeGreen.opacity(0.25))
                    .frame(width: 140, height: 140)
                    .blur(radius: 35)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(Colors.safeGreen)
                    .scaleEffect(iconScale)
            }
            .onAppear {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.5).delay(0.3)) {
                    iconScale = 1.0
                }
            }

            VStack(spacing: Spacing.xs) {
                Text("You're Ready")
                    .font(Typography.displayMedium)
                    .foregroundColor(.white)

                Text("OnTheRecord is set up and ready to protect you.")
                    .font(Typography.bodyMedium)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
            }
            .slideUpEntrance(isPresented: isAppeared, delay: 0.2)

            GlassCard(material: .ultraThinMaterial, padding: Spacing.md) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    ForEach(Array(readyItems.enumerated()), id: \.offset) { index, item in
                        ReadyItem(text: item)
                            .staggeredEntrance(isPresented: isAppeared, index: index + 2)
                    }
                }
            }
            .padding(.horizontal, Spacing.md)

            Spacer()

            PremiumPrimaryButton(
                title: "Get Started",
                icon: "arrow.right",
                color: Colors.witnessRed
            ) {
                UserDefaults.standard.set(true, forKey: "onboarding_complete")
                dismiss()
            }
            .padding(.horizontal, Spacing.md)
            .slideUpEntrance(isPresented: isAppeared, delay: 0.5)
        }
        .padding()
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                isAppeared = true
            }
        }
    }

    private var readyItems: [String] {
        [
            "Tap the red button to start recording",
            "Alerts will be sent to your contacts",
            "Footage uploads automatically",
            "Practice the passcode drill regularly"
        ]
    }
}

struct ReadyItem: View {
    let text: String

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16))
                .foregroundColor(Colors.safeGreen)
            Text(text)
                .font(Typography.bodyMedium)
                .foregroundColor(.white)
        }
    }
}

// MARK: - Safe PIN Onboarding Page

struct SafePINOnboardingPage: View {
    @Binding var currentPage: Int
    let nextTag: Int

    @State private var pin1 = ""
    @State private var pin2 = ""
    @State private var saved = false
    @State private var isAppeared = false

    private let pinColor = Color(red: 0.2, green: 0.8, blue: 0.3)

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            ZStack {
                Circle()
                    .fill(pinColor.opacity(0.2))
                    .frame(width: 100, height: 100)
                    .blur(radius: 25)

                Image(systemName: "dial.medium.fill")
                    .font(.system(size: 60))
                    .foregroundColor(pinColor)
            }
            .fadeScaleEntrance(isPresented: isAppeared)

            VStack(spacing: Spacing.xs) {
                Text("Set Your Safe PIN")
                    .font(Typography.headline1)
                    .foregroundColor(.white)

                Text("You need a PIN to stop a recording. Without it, no one can force your recording to stop.")
                    .font(Typography.bodyMedium)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
            }
            .slideUpEntrance(isPresented: isAppeared, delay: 0.1)

            GlassCard(material: .ultraThinMaterial, padding: Spacing.md) {
                VStack(spacing: Spacing.sm) {
                    SecureField("New PIN (4 digits)", text: $pin1)
                        .keyboardType(.numberPad)
                        .font(Typography.bodyLarge)
                        .padding(Spacing.sm)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(Spacing.Radius.xs)
                        .foregroundColor(.white)
                        .onChange(of: pin1) { _, newValue in
                            pin1 = String(newValue.filter { $0.isNumber }.prefix(4))
                        }

                    SecureField("Confirm PIN", text: $pin2)
                        .keyboardType(.numberPad)
                        .font(Typography.bodyLarge)
                        .padding(Spacing.sm)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(Spacing.Radius.xs)
                        .foregroundColor(.white)
                        .onChange(of: pin2) { _, newValue in
                            pin2 = String(newValue.filter { $0.isNumber }.prefix(4))
                        }

                    if !pin1.isEmpty && !pin2.isEmpty && pin1 != pin2 {
                        HStack(spacing: Spacing.xxs) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 12))
                            Text("PINs don't match")
                                .font(Typography.caption)
                        }
                        .foregroundColor(Colors.alertOrange)
                    }
                }
            }
            .padding(.horizontal, Spacing.md)
            .staggeredEntrance(isPresented: isAppeared, index: 2)

            VStack(spacing: Spacing.sm) {
                PremiumPrimaryButton(
                    title: "Save PIN and Continue",
                    icon: "arrow.right",
                    color: isValid ? pinColor : Color.gray
                ) {
                    UserDefaults.standard.set(pin1, forKey: "safe_pin")
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                    saved = true
                    currentPage = nextTag
                }
                .disabled(!isValid)
                .opacity(isValid ? 1.0 : 0.6)

                Button {
                    currentPage = nextTag
                } label: {
                    Text("Skip for now (not recommended)")
                        .font(Typography.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, Spacing.md)
            .staggeredEntrance(isPresented: isAppeared, index: 3)

            Spacer()
        }
        .padding()
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                isAppeared = true
            }
        }
    }

    private var isValid: Bool {
        pin1.count == 4 && pin1 == pin2
    }
}

// MARK: - Invite Page

struct InvitePage: View {
    @State private var isAppeared = false
    
    // TODO: Replace with real App Store URL
    private let appURL = URL(string: "https://apps.apple.com/app/id673949313")!
    private let shareMessage = "I'm using OnTheRecord to protect myself. It's a black box for your phone. Download it here:"

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 100, height: 100)
                    .blur(radius: 25)

                Image(systemName: "person.3.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
            }
            .fadeScaleEntrance(isPresented: isAppeared)

            VStack(spacing: Spacing.xs) {
                Text("Build Your Network")
                    .font(Typography.headline1)
                    .foregroundColor(.white)

                Text("Safety is stronger in numbers.\nInvite family and friends to join your safety network.")
                    .font(Typography.bodyMedium)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
            }
            .slideUpEntrance(isPresented: isAppeared, delay: 0.1)
            
            VStack(spacing: Spacing.md) {
                ShareLink(item: appURL, message: Text(shareMessage)) {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 18, weight: .semibold))
                        Text("Invite Contacts")
                            .font(Typography.bodyLarge)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(Spacing.Radius.md)
                }
            }
            .padding(.horizontal, Spacing.lg)
            .staggeredEntrance(isPresented: isAppeared, index: 2)

            Spacer()
            
            Text("Tip: Witnesses who are also users can receive richer alerts")
                .font(Typography.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                isAppeared = true
            }
        }
    }
}

#Preview {
    OnboardingView()
        .environmentObject(AlertService())
}
