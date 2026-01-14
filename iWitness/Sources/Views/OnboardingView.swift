import SwiftUI
import AVFoundation
import CoreLocation

struct OnboardingView: View {
    @Environment(\.dismiss) var dismiss
    @State private var currentPage = 0

    var body: some View {
        TabView(selection: $currentPage) {
            WelcomePage()
                .tag(0)

            PermissionsPage()
                .tag(1)

            ContactsSetupPage()
                .tag(2)

            StorageSetupPage()
                .tag(3)

            SecurityDrillPage()
                .tag(4)

            CompletePage(dismiss: dismiss)
                .tag(5)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
    }
}

// MARK: - Welcome Page

struct WelcomePage: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "video.badge.checkmark")
                .font(.system(size: 80))
                .foregroundColor(.red)

            Text("Welcome to iWitness")
                .font(.largeTitle.bold())

            Text("Document what matters.\nProtect what's important.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            Spacer()

            VStack(spacing: 12) {
                FeatureRow(icon: "video.fill", text: "Dual-camera recording")
                FeatureRow(icon: "lock.shield.fill", text: "Encrypted cloud backup")
                FeatureRow(icon: "bell.fill", text: "Instant emergency alerts")
                FeatureRow(icon: "person.2.fill", text: "Community witness network")
            }
            .padding()

            Spacer()

            Text("Swipe to continue →")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}

struct FeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.red)
                .frame(width: 30)
            Text(text)
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

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)

            Text("Permissions")
                .font(.title.bold())

            Text("iWitness needs these permissions to protect you")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            VStack(spacing: 16) {
                PermissionButton(
                    icon: "camera.fill",
                    title: "Camera",
                    description: "Record video from both cameras",
                    isGranted: cameraGranted
                ) {
                    Task {
                        cameraGranted = await requestCamera()
                    }
                }

                PermissionButton(
                    icon: "mic.fill",
                    title: "Microphone",
                    description: "Capture audio evidence",
                    isGranted: microphoneGranted
                ) {
                    Task {
                        microphoneGranted = await requestMicrophone()
                    }
                }

                PermissionButton(
                    icon: "location.fill",
                    title: "Location",
                    description: "Share your location with contacts",
                    isGranted: locationGranted
                ) {
                    requestLocation()
                    locationGranted = true
                }

                PermissionButton(
                    icon: "bell.fill",
                    title: "Notifications",
                    description: "Receive community alerts",
                    isGranted: notificationsGranted
                ) {
                    Task {
                        notificationsGranted = await requestNotifications()
                    }
                }
            }
            .padding()

            Spacer()
        }
        .padding()
        .onAppear {
            checkExistingPermissions()
        }
    }

    private func checkExistingPermissions() {
        cameraGranted = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        locationGranted = CLLocationManager.authorizationStatus() == .authorizedWhenInUse ||
                         CLLocationManager.authorizationStatus() == .authorizedAlways
    }

    private func requestCamera() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    private func requestMicrophone() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    private func requestLocation() {
        CLLocationManager().requestWhenInUseAuthorization()
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

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(isGranted ? .green : .primary)
                    .frame(width: 30)

                VStack(alignment: .leading) {
                    Text(title)
                        .font(.headline)
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isGranted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else {
                    Text("Enable")
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isGranted)
    }
}

// MARK: - Contacts Setup Page

struct ContactsSetupPage: View {
    @EnvironmentObject var alertService: AlertService
    @State private var showingAddContact = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "person.2.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)

            Text("Emergency Contacts")
                .font(.title.bold())

            Text("Who should be notified when you activate Witness mode?")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            if alertService.contacts.isEmpty {
                VStack(spacing: 12) {
                    Text("No contacts added yet")
                        .foregroundColor(.secondary)

                    Button("Add Contact") {
                        showingAddContact = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                VStack(spacing: 8) {
                    ForEach(alertService.contacts) { contact in
                        HStack {
                            Image(systemName: "person.fill")
                            Text(contact.name)
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                    }

                    Button("Add Another") {
                        showingAddContact = true
                    }
                }
            }

            Spacer()

            Text("You can add more contacts later in Settings")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .sheet(isPresented: $showingAddContact) {
            AddContactView()
        }
    }
}

// MARK: - Storage Setup Page

struct StorageSetupPage: View {
    @State private var showingNASSetup = false
    @State private var hasNASConfigured = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "externaldrive.badge.checkmark")
                .font(.system(size: 60))
                .foregroundColor(.orange)

            Text("Backup Storage")
                .font(.title.bold())

            Text("Where should your footage be stored?")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            VStack(spacing: 16) {
                StorageOption(
                    icon: "externaldrive.fill",
                    title: "Offsite Backup",
                    description: "Your home server or NAS",
                    isConfigured: hasNASConfigured
                ) {
                    showingNASSetup = true
                }

                StorageOption(
                    icon: "cloud.fill",
                    title: "Cloud Backup",
                    description: "Cloudflare R2 (coming soon)",
                    isConfigured: false,
                    isDisabled: true
                ) {
                    // Coming soon
                }
            }
            .padding()

            Spacer()

            Text("Footage is encrypted before upload")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .sheet(isPresented: $showingNASSetup) {
            NASSetupView()
        }
        .onAppear {
            hasNASConfigured = UserDefaults.standard.string(forKey: "nas_url") != nil
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

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(isConfigured ? .green : .primary)
                    .frame(width: 40)

                VStack(alignment: .leading) {
                    Text(title)
                        .font(.headline)
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isConfigured {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else if !isDisabled {
                    Text("Setup")
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            .opacity(isDisabled ? 0.5 : 1)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isDisabled || isConfigured)
    }
}

// MARK: - Security Drill Page

struct SecurityDrillPage: View {
    @State private var hasCompletedDrill = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 60))
                .foregroundColor(.yellow)

            Text("Security Drill")
                .font(.title.bold())

            Text("Practice securing your phone quickly")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 16) {
                DrillStep(number: 1, text: "Hold SIDE + VOLUME buttons")
                DrillStep(number: 2, text: "Wait for power-off screen")
                DrillStep(number: 3, text: "Press CANCEL")
                DrillStep(number: 4, text: "Face ID is now disabled!")
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)

            Button(hasCompletedDrill ? "Completed!" : "I've Practiced This") {
                hasCompletedDrill = true
            }
            .buttonStyle(.borderedProminent)
            .tint(hasCompletedDrill ? .green : .blue)

            Spacer()

            Text("This ensures only your PIN can unlock your phone")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}

struct DrillStep: View {
    let number: Int
    let text: String

    var body: some View {
        HStack {
            Text("\(number)")
                .font(.headline)
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(Color.yellow)
                .clipShape(Circle())

            Text(text)
        }
    }
}

// MARK: - Complete Page

struct CompletePage: View {
    let dismiss: DismissAction

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.green)

            Text("You're Ready")
                .font(.largeTitle.bold())

            Text("iWitness is set up and ready to protect you.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                ReadyItem(text: "Tap the red button to start recording")
                ReadyItem(text: "Alerts will be sent to your contacts")
                ReadyItem(text: "Footage uploads automatically")
                ReadyItem(text: "Practice the passcode drill regularly")
            }
            .padding()

            Spacer()

            Button {
                UserDefaults.standard.set(true, forKey: "onboarding_complete")
                dismiss()
            } label: {
                Text("Get Started")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red)
                    .cornerRadius(12)
            }
        }
        .padding()
    }
}

struct ReadyItem: View {
    let text: String

    var body: some View {
        HStack {
            Image(systemName: "checkmark")
                .foregroundColor(.green)
            Text(text)
        }
    }
}

#Preview {
    OnboardingView()
        .environmentObject(AlertService())
}
