import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var alertService: AlertService
    @EnvironmentObject var uploadService: UploadService

    @State private var showingAddContact = false
    @State private var showingNASSetup = false
    @State private var showingCloudSetup = false
    @State private var showingTwilioSetup = false
    @State private var showingSafePINSetup = false
    @State private var showingDuressPINSetup = false
    @State private var showingStreamingSetup = false

    @EnvironmentObject var liveStreamService: LiveStreamService

    var body: some View {
        NavigationStack {
            ZStack {
                // Premium ambient background
                AmbientOrbsBackground(accentColor: Colors.witnessRed, intensity: 0.08)

                List {
                // Emergency Contacts Section
                Section {
                    ForEach(alertService.contacts) { contact in
                        ContactRow(contact: contact)
                    }
                    .onDelete(perform: deleteContact)

                    Button {
                        showingAddContact = true
                    } label: {
                        Label("Add Contact", systemImage: "plus")
                    }
                } header: {
                    Text("Emergency Contacts")
                } footer: {
                    Text("These contacts will be notified when you activate Witness mode.")
                }

                // Upload Destinations Section
                Section {
                    Button {
                        showingNASSetup = true
                    } label: {
                        HStack {
                            Label("Offsite Backup", systemImage: "externaldrive.fill")
                            Spacer()
                            if hasNASConfigured {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            }
                        }
                    }

                    Button {
                        showingCloudSetup = true
                    } label: {
                        HStack {
                            Label("Cloud Backup", systemImage: "cloud.fill")
                            Spacer()
                            if hasCloudConfigured {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            }
                        }
                    }

                    // Browse recordings on NAS
                    if hasNASConfigured {
                        NavigationLink {
                            RecordingsView()
                        } label: {
                            HStack {
                                Label("View Recordings", systemImage: "play.rectangle.fill")
                                Spacer()
                                Image(systemName: "lock.shield")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Upload Destinations")
                } footer: {
                    Text("Footage is encrypted before upload. Configure multiple destinations for redundancy.")
                }

                // Live Streaming Section
                Section {
                    Button {
                        showingStreamingSetup = true
                    } label: {
                        HStack {
                            Label("Live Stream", systemImage: "dot.radiowaves.left.and.right")
                            Spacer()
                            if liveStreamService.isConfigured {
                                Text("Configured")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            } else {
                                Text("Not Set Up")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    Toggle("Enable Live Streaming", isOn: Binding(
                        get: { UserDefaults.standard.bool(forKey: "live_stream_enabled") },
                        set: { UserDefaults.standard.set($0, forKey: "live_stream_enabled") }
                    ))
                    .disabled(!liveStreamService.isConfigured)

                    Toggle("Auto-share Link with Contacts", isOn: Binding(
                        get: { UserDefaults.standard.bool(forKey: "auto_share_stream") },
                        set: { UserDefaults.standard.set($0, forKey: "auto_share_stream") }
                    ))
                    .disabled(!liveStreamService.isConfigured)
                } header: {
                    Text("Live Streaming")
                } footer: {
                    Text("Stream video in real-time to cloud storage. Contacts receive a link to watch live.")
                }

                // SMS/Twilio Section
                Section {
                    Button {
                        showingTwilioSetup = true
                    } label: {
                        HStack {
                            Label("Twilio SMS", systemImage: "message.fill")
                            Spacer()
                            Text(alertService.twilioStatus.rawValue)
                                .font(.caption)
                                .foregroundColor(twilioStatusColor)
                        }
                    }

                    Toggle("Use Twilio for Alerts", isOn: $alertService.useTwilio)
                        .disabled(alertService.twilioConfig == nil)
                } header: {
                    Text("Background SMS")
                } footer: {
                    Text("Twilio enables automatic SMS without opening Messages app. Mock mode available for testing.")
                }

                // Siri & Watch Section
                Section {
                    NavigationLink {
                        SiriSettingsView()
                    } label: {
                        HStack {
                            Label("Siri Shortcuts", systemImage: "waveform")
                            Spacer()
                            if SiriShortcutManager.shared.isShortcutDonated {
                                Text("Active")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        }
                    }

                    HStack {
                        Label("Apple Watch", systemImage: "applewatch")
                        Spacer()
                        if PhoneConnectivityManager.shared.isWatchReachable {
                            Text("Connected")
                                .font(.caption)
                                .foregroundColor(.green)
                        } else if PhoneConnectivityManager.shared.isWatchPaired {
                            Text("Paired")
                                .font(.caption)
                                .foregroundColor(.orange)
                        } else {
                            Text("Not Paired")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Voice & Watch")
                } footer: {
                    Text("Use Siri or your Apple Watch to activate iWitness hands-free.")
                }

                // Recording Settings Section
                Section {
                    NavigationLink {
                        QualitySettingsView()
                    } label: {
                        Label("Video Quality", systemImage: "video.fill")
                    }

                    Button {
                        showingSafePINSetup = true
                    } label: {
                        HStack {
                            Label("Safe PIN", systemImage: "dial.medium.fill")
                            Spacer()
                            Text(hasSafePIN ? "Set" : "Default")
                                .font(.caption)
                                .foregroundColor(hasSafePIN ? .green : .orange)
                        }
                    }

                    Button {
                        showingDuressPINSetup = true
                    } label: {
                        HStack {
                            Label("Duress PIN", systemImage: "exclamationmark.shield.fill")
                            Spacer()
                            Text(UserDefaults.standard.string(forKey: "duress_pin") == nil ? "Not Set" : "Set")
                                .font(.caption)
                                .foregroundColor(UserDefaults.standard.string(forKey: "duress_pin") == nil ? .secondary : .orange)
                        }
                    }

                    Toggle("Enable Stealth Blackout Gesture", isOn: Binding(
                        get: { UserDefaults.standard.bool(forKey: "stealth_blackout_gesture") },
                        set: { UserDefaults.standard.set($0, forKey: "stealth_blackout_gesture") }
                    ))

                    Toggle("Start Recording in Blackout", isOn: Binding(
                        get: { UserDefaults.standard.bool(forKey: "stealth_start_blackout") },
                        set: { UserDefaults.standard.set($0, forKey: "stealth_start_blackout") }
                    ))

                    NavigationLink {
                        GuidedAccessSetupView()
                    } label: {
                        Label("Guided Access Setup", systemImage: "lock.shield")
                    }

                    NavigationLink {
                        PasscodeDrillView()
                    } label: {
                        Label("Passcode Drill", systemImage: "hand.tap.fill")
                    }
                } header: {
                    Text("Security & Recording")
                } footer: {
                    Text("Set a Safe PIN to end a recording. A Duress PIN can silently escalate instead of stopping.")
                }

                // Legal Section
                Section {
                    NavigationLink {
                        KnowYourRightsView()
                    } label: {
                        Label("Know Your Rights", systemImage: "book.fill")
                    }

                    NavigationLink {
                        LegalResourcesView()
                    } label: {
                        Label("Legal Resources", systemImage: "building.columns.fill")
                    }
                } header: {
                    Text("Legal")
                }

                // About Section
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }

                    Link(destination: URL(string: "https://iwitness.app/privacy")!) {
                        Label("Privacy Policy", systemImage: "hand.raised.fill")
                    }

                    Link(destination: URL(string: "https://iwitness.app/terms")!) {
                        Label("Terms of Service", systemImage: "doc.text.fill")
                    }
                } header: {
                    Text("About")
                }
                }
                .scrollContentBackground(.hidden)
                .listRowBackground(Color.white.opacity(0.05))
            }
            .navigationTitle("Settings")
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showingAddContact) {
                AddContactView()
            }
            .sheet(isPresented: $showingNASSetup) {
                NASSetupView()
            }
            .sheet(isPresented: $showingCloudSetup) {
                CloudSetupView()
            }
            .sheet(isPresented: $showingTwilioSetup) {
                TwilioSetupView()
            }
            .sheet(isPresented: $showingSafePINSetup) {
                SafePINSetupView()
            }
            .sheet(isPresented: $showingDuressPINSetup) {
                DuressPINSetupView()
            }
            .sheet(isPresented: $showingStreamingSetup) {
                StreamingSetupView()
            }
        }
    }

    private var hasSafePIN: Bool {
        UserDefaults.standard.string(forKey: "safe_pin") != nil
    }

    private var hasNASConfigured: Bool {
        // Check UserDefaults for NAS config
        UserDefaults.standard.string(forKey: "nas_url") != nil
    }

    private var hasCloudConfigured: Bool {
        // Check UserDefaults for cloud config
        UserDefaults.standard.string(forKey: "cloud_access_key") != nil
    }

    private var twilioStatusColor: Color {
        switch alertService.twilioStatus {
        case .notConfigured: return .secondary
        case .configured: return .green
        case .sending: return .orange
        case .success: return .green
        case .failed: return .red
        case .mockMode: return .blue
        }
    }

    private func deleteContact(at offsets: IndexSet) {
        for index in offsets {
            let contact = alertService.contacts[index]
            alertService.removeContact(contact)
        }
    }
}

// MARK: - Contact Row

struct ContactRow: View {
    let contact: AlertService.EmergencyContact

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Circle()
                .fill(Color.blue.opacity(0.2))
                .frame(width: 40, height: 40)
                .overlay(
                    Text(contact.name.prefix(1).uppercased())
                        .font(Typography.bodyMedium)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Spacing.xs) {
                    Text(contact.name)
                        .font(Typography.bodyMedium)
                        .fontWeight(.semibold)

                    if contact.isLawyer {
                        Text("LAWYER")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(3)
                    }
                }

                Text(contact.phone)
                    .font(Typography.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(Colors.safeGreen)
                .font(.system(size: 18))
        }
        .padding(.vertical, Spacing.xxs)
    }
}

// MARK: - Add Contact View

struct AddContactView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var alertService: AlertService

    @State private var name = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var isLawyer = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("Phone", text: $phone)
                        .keyboardType(.phonePad)
                    TextField("Email (optional)", text: $email)
                        .keyboardType(.emailAddress)
                }

                Section {
                    Toggle("This is my lawyer", isOn: $isLawyer)
                } footer: {
                    Text("Lawyers receive escalation alerts if you don't mark safe.")
                }
            }
            .navigationTitle("Add Contact")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveContact()
                    }
                    .disabled(name.isEmpty || phone.isEmpty)
                }
            }
        }
    }

    private func saveContact() {
        let contact = AlertService.EmergencyContact(
            name: name,
            phone: phone,
            email: email.isEmpty ? nil : email,
            isLawyer: isLawyer,
            priority: alertService.contacts.count + 1
        )
        alertService.addContact(contact)
        dismiss()
    }
}

// MARK: - NAS Setup View

struct NASSetupView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var uploadService: UploadService

    @State private var nasURL = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isTesting = false
    @State private var testResult: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("WebDAV URL", text: $nasURL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                    TextField("Username", text: $username)
                        .autocapitalization(.none)
                    SecureField("Password", text: $password)
                } header: {
                    Text("Backup Server Connection")
                } footer: {
                    Text("Connect to a home server or NAS via WebDAV. For Ugreen, enable WebDAV in UGOS Pro settings.")
                }

                Section {
                    Button {
                        testConnection()
                    } label: {
                        if isTesting {
                            ProgressView()
                        } else {
                            Text("Test Connection")
                        }
                    }
                    .disabled(nasURL.isEmpty || username.isEmpty || password.isEmpty)

                    if let result = testResult {
                        Text(result)
                            .foregroundColor(result.contains("Success") ? .green : .red)
                    }
                }
            }
            .navigationTitle("Offsite Backup")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveNASConfig()
                    }
                    .disabled(nasURL.isEmpty || username.isEmpty || password.isEmpty)
                }
            }
        }
    }

    private func testConnection() {
        isTesting = true
        testResult = nil

        Task {
            // Test WebDAV connection
            guard let url = URL(string: nasURL) else {
                testResult = "Invalid URL"
                isTesting = false
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "OPTIONS"

            let authString = "\(username):\(password)"
            if let authData = authString.data(using: .utf8) {
                let base64Auth = authData.base64EncodedString()
                request.setValue("Basic \(base64Auth)", forHTTPHeaderField: "Authorization")
            }

            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let httpResponse = response as? HTTPURLResponse,
                   (200...299).contains(httpResponse.statusCode) {
                    testResult = "Success! Connection verified."
                } else {
                    testResult = "Connection failed. Check credentials."
                }
            } catch {
                testResult = "Error: \(error.localizedDescription)"
            }

            isTesting = false
        }
    }

    private func saveNASConfig() {
        UserDefaults.standard.set(nasURL, forKey: "nas_url")
        UserDefaults.standard.set(username, forKey: "nas_username")
        // Store password in Keychain
        _ = KeychainHelper.shared.save(service: "iWitness", account: "nas_password", value: password)

        // Configure upload service
        if let url = URL(string: nasURL) {
            uploadService.addNASDestination(url: url, username: username, password: password)
        }

        dismiss()
    }
}

// MARK: - Cloud Setup View

struct CloudSetupView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var uploadService: UploadService

    @State private var accountID = ""
    @State private var bucketName = ""
    @State private var accessKeyID = ""
    @State private var secretAccessKey = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Account ID", text: $accountID)
                        .autocapitalization(.none)
                    TextField("Bucket Name", text: $bucketName)
                        .autocapitalization(.none)
                    TextField("Access Key ID", text: $accessKeyID)
                        .autocapitalization(.none)
                    SecureField("Secret Access Key", text: $secretAccessKey)
                } header: {
                    Text("Cloudflare R2")
                } footer: {
                    Text("Get these from your Cloudflare dashboard under R2 > Manage R2 API Tokens")
                }
            }
            .navigationTitle("Cloud Setup")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveCloudConfig()
                    }
                    .disabled(accountID.isEmpty || bucketName.isEmpty || accessKeyID.isEmpty || secretAccessKey.isEmpty)
                }
            }
        }
    }

    private func saveCloudConfig() {
        UserDefaults.standard.set(accountID, forKey: "cloud_account_id")
        UserDefaults.standard.set(bucketName, forKey: "cloud_bucket")
        UserDefaults.standard.set(accessKeyID, forKey: "cloud_access_key")
        // Store secret in Keychain
        _ = KeychainHelper.shared.save(service: "iWitness", account: "cloud_secret_key", value: secretAccessKey)

        // Configure upload service
        uploadService.addR2Destination(
            accountID: accountID,
            bucketName: bucketName,
            accessKeyID: accessKeyID,
            secretAccessKey: secretAccessKey
        )

        dismiss()
    }
}

// MARK: - Placeholder Views

struct QualitySettingsView: View {
    var body: some View {
        Text("Quality Settings")
            .navigationTitle("Video Quality")
    }
}

struct GuidedAccessSetupView: View {
    @State private var isAppeared = false

    private let steps: [(title: String, content: String)] = [
        ("Step 1", "Go to Settings → Accessibility → Guided Access"),
        ("Step 2", "Turn on Guided Access"),
        ("Step 3", "Set a passcode (use a DIFFERENT passcode than your phone unlock)"),
        ("Step 4", "Enable 'Accessibility Shortcut'"),
        ("During Recording", "Triple-click the side button to activate Guided Access. This prevents Control Center access and exiting iWitness.")
    ]

    var body: some View {
        ZStack {
            AmbientOrbsBackground(accentColor: .purple, intensity: 0.08)

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    GlassCard(material: .ultraThinMaterial, padding: Spacing.md) {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "lock.iphone")
                                .font(.system(size: 24))
                                .foregroundColor(.purple)
                            Text("Guided Access locks your iPhone to iWitness and prevents exiting the app.")
                                .font(Typography.bodyMedium)
                                .foregroundColor(.secondary)
                        }
                    }
                    .fadeScaleEntrance(isPresented: isAppeared)

                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        GlassCard(material: .ultraThinMaterial, padding: Spacing.md) {
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Text(step.title)
                                    .font(Typography.bodyLarge)
                                    .fontWeight(.semibold)
                                    .foregroundColor(index == steps.count - 1 ? Colors.alertOrange : .white)
                                Text(step.content)
                                    .font(Typography.bodyMedium)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .staggeredEntrance(isPresented: isAppeared, index: index + 1)
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Guided Access")
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                isAppeared = true
            }
        }
    }
}

struct PasscodeDrillView: View {
    @State private var drillStarted = false
    @State private var drillTime: TimeInterval?
    @State private var isAppeared = false

    var body: some View {
        ZStack {
            AmbientOrbsBackground(accentColor: .yellow, intensity: 0.08)

            VStack(spacing: Spacing.lg) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(Color.yellow.opacity(0.2))
                        .frame(width: 120, height: 120)
                        .blur(radius: 30)

                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.yellow)
                }
                .fadeScaleEntrance(isPresented: isAppeared)

                VStack(spacing: Spacing.xs) {
                    Text("Force Passcode Drill")
                        .font(Typography.headline1)
                        .foregroundColor(.white)

                    Text("Practice disabling Face ID quickly")
                        .font(Typography.bodyMedium)
                        .foregroundColor(.secondary)
                }
                .slideUpEntrance(isPresented: isAppeared, delay: 0.1)

                GlassCard(material: .ultraThinMaterial, padding: Spacing.md) {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        ForEach(Array(drillSteps.enumerated()), id: \.offset) { index, step in
                            HStack(spacing: Spacing.sm) {
                                Text("\(index + 1)")
                                    .font(Typography.bodyMedium)
                                    .fontWeight(.bold)
                                    .foregroundColor(.black)
                                    .frame(width: 24, height: 24)
                                    .background(Color.yellow)
                                    .clipShape(Circle())
                                Text(step)
                                    .font(Typography.bodyMedium)
                                    .foregroundColor(.white)
                            }
                            .staggeredEntrance(isPresented: isAppeared, index: index + 2)
                        }
                    }
                }
                .padding(.horizontal, Spacing.md)

                if let time = drillTime {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "stopwatch.fill")
                        Text("Your time: \(String(format: "%.1f", time)) seconds")
                            .font(Typography.headline2)
                    }
                    .foregroundColor(time < 2 ? Colors.safeGreen : .orange)
                    .padding(Spacing.md)
                    .glassBackground(cornerRadius: Spacing.Radius.md)
                }

                PremiumPrimaryButton(
                    title: drillStarted ? "STOP" : "START DRILL",
                    icon: drillStarted ? "stop.fill" : "play.fill",
                    color: drillStarted ? Colors.alertOrange : .yellow
                ) {
                    if drillStarted {
                        drillTime = Date().timeIntervalSince(Date())
                        drillStarted = false
                    } else {
                        drillStarted = true
                    }
                }
                .padding(.horizontal, Spacing.md)

                Spacer()
            }
            .padding()
        }
        .navigationTitle("Passcode Drill")
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                isAppeared = true
            }
        }
    }

    private var drillSteps: [String] {
        [
            "Hold SIDE + VOLUME buttons",
            "Wait for 'slide to power off' screen",
            "Press CANCEL",
            "Face ID is now disabled!"
        ]
    }
}

struct KnowYourRightsView: View {
    @State private var isAppeared = false

    var body: some View {
        ZStack {
            AmbientOrbsBackground(accentColor: .blue, intensity: 0.08)

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    ForEach(Array(rights.enumerated()), id: \.offset) { index, right in
                        RightsCard(title: right.title, content: right.content)
                            .staggeredEntrance(isPresented: isAppeared, index: index)
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Know Your Rights")
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                isAppeared = true
            }
        }
    }

    private var rights: [(title: String, content: String)] {
        [
            ("You Have the Right to Remain Silent",
             "You do not have to answer questions about where you were born, your immigration status, or any other questions."),
            ("You Do Not Have to Open Your Door",
             "ICE cannot enter your home without a judicial warrant signed by a judge. An ICE administrative warrant is NOT enough."),
            ("You Have the Right to a Lawyer",
             "If you are detained, you have the right to speak with an attorney before answering any questions."),
            ("You Have the Right to Record",
             "You have the right to record interactions with law enforcement in public spaces.")
        ]
    }
}

struct RightsCard: View {
    let title: String
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .font(Typography.bodyLarge)
                .fontWeight(.semibold)
                .foregroundColor(.white)
            Text(content)
                .font(Typography.bodyMedium)
                .foregroundColor(.secondary)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassBackground(cornerRadius: Spacing.Radius.md)
    }
}

struct LegalResourcesView: View {
    @State private var isAppeared = false

    private let resources: [(name: String, url: String, icon: String)] = [
        ("ACLU Know Your Rights", "https://www.aclu.org/know-your-rights/immigrants-rights", "hand.raised.fill"),
        ("National Immigration Law Center", "https://www.nilc.org", "building.columns.fill"),
        ("United We Dream", "https://unitedwedream.org", "person.3.fill")
    ]

    var body: some View {
        ZStack {
            AmbientOrbsBackground(accentColor: .blue, intensity: 0.08)

            ScrollView {
                VStack(spacing: Spacing.md) {
                    ForEach(Array(resources.enumerated()), id: \.offset) { index, resource in
                        Link(destination: URL(string: resource.url)!) {
                            HStack(spacing: Spacing.sm) {
                                Image(systemName: resource.icon)
                                    .font(.system(size: 20))
                                    .foregroundColor(.blue)
                                    .frame(width: 32)

                                Text(resource.name)
                                    .font(Typography.bodyMedium)
                                    .fontWeight(.medium)
                                    .foregroundColor(.white)

                                Spacer()

                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                            }
                            .padding(Spacing.md)
                            .glassBackground(cornerRadius: Spacing.Radius.md)
                        }
                        .staggeredEntrance(isPresented: isAppeared, index: index)
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Legal Resources")
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                isAppeared = true
            }
        }
    }
}

// MARK: - Siri Settings View

struct SiriSettingsView: View {
    @State private var showingActivateSheet = false
    @State private var showingSafeSheet = false
    @State private var isAppeared = false

    var body: some View {
        ZStack {
            AmbientOrbsBackground(accentColor: .purple, intensity: 0.08)

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    // Explanation
                    GlassCard(material: .ultraThinMaterial, padding: Spacing.md) {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "waveform")
                                .font(.system(size: 24))
                                .foregroundColor(.purple)
                            VStack(alignment: .leading, spacing: Spacing.xxs) {
                                Text("Voice Activation")
                                    .font(Typography.bodyLarge)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                Text("Add Siri Shortcuts to activate iWitness or mark yourself safe using just your voice.")
                                    .font(Typography.bodyMedium)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .fadeScaleEntrance(isPresented: isAppeared)

                    // Activate Witness Shortcut
                    GlassCard(material: .ultraThinMaterial, padding: Spacing.md) {
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            HStack {
                                Image(systemName: "video.fill")
                                    .foregroundColor(Colors.witnessRed)
                                    .font(.title2)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Activate Witness")
                                        .font(Typography.bodyLarge)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)
                                    Text("Start recording and send alerts")
                                        .font(Typography.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            Text("Example phrases:")
                                .font(Typography.caption)
                                .foregroundColor(.secondary)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("\"Hey Siri, Witness Mode\"")
                                Text("\"Hey Siri, Start Recording\"")
                                Text("\"Hey Siri, Emergency Record\"")
                            }
                            .font(Typography.caption)
                            .italic()
                            .foregroundColor(.white.opacity(0.7))

                            AddToSiriButton(
                                activityType: SiriShortcutManager.activateActivityType,
                                title: "Activate Witness",
                                phrase: "Witness Mode"
                            )
                        }
                    }
                    .staggeredEntrance(isPresented: isAppeared, index: 1)

                    // Safe Shortcut
                    GlassCard(material: .ultraThinMaterial, padding: Spacing.md) {
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            HStack {
                                Image(systemName: "checkmark.shield.fill")
                                    .foregroundColor(Colors.safeGreen)
                                    .font(.title2)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("I'm Safe")
                                        .font(Typography.bodyLarge)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)
                                    Text("Stop recording and notify contacts")
                                        .font(Typography.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            Text("Example phrases:")
                                .font(Typography.caption)
                                .foregroundColor(.secondary)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("\"Hey Siri, I'm Safe\"")
                                Text("\"Hey Siri, Stop Witness\"")
                                Text("\"Hey Siri, All Clear\"")
                            }
                            .font(Typography.caption)
                            .italic()
                            .foregroundColor(.white.opacity(0.7))

                            AddToSiriButton(
                                activityType: SiriShortcutManager.safeActivityType,
                                title: "I'm Safe",
                                phrase: "I'm Safe"
                            )
                        }
                    }
                    .staggeredEntrance(isPresented: isAppeared, index: 2)

                    // Apple Watch section
                    GlassCard(material: .ultraThinMaterial, padding: Spacing.md) {
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            HStack {
                                Image(systemName: "applewatch")
                                    .foregroundColor(.blue)
                                    .font(.title2)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Apple Watch")
                                        .font(Typography.bodyLarge)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)
                                    Text("Activate from your wrist")
                                        .font(Typography.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            Text("With the iWitness Watch app installed, you can:")
                                .font(Typography.caption)
                                .foregroundColor(.secondary)

                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                WatchFeatureRow(text: "Tap to activate recording")
                                WatchFeatureRow(text: "Mark yourself safe")
                                WatchFeatureRow(text: "Request help escalation")
                                WatchFeatureRow(text: "See upload status")
                            }
                        }
                    }
                    .staggeredEntrance(isPresented: isAppeared, index: 3)

                    // Tips
                    GlassCard(material: .ultraThinMaterial, padding: Spacing.md) {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text("Tips")
                                .font(Typography.bodyLarge)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)

                            Text("• Practice saying your trigger phrase aloud")
                                .font(Typography.caption)
                                .foregroundColor(.secondary)
                            Text("• Siri works even when your phone is locked")
                                .font(Typography.caption)
                                .foregroundColor(.secondary)
                            Text("• Use Apple Watch in silent situations")
                                .font(Typography.caption)
                                .foregroundColor(.secondary)
                            Text("• Voice activation may not work in noisy environments")
                                .font(Typography.caption)
                                .foregroundColor(.orange)
                        }
                    }
                    .staggeredEntrance(isPresented: isAppeared, index: 4)
                }
                .padding()
            }
        }
        .navigationTitle("Siri & Voice")
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                isAppeared = true
            }
        }
    }
}

struct WatchFeatureRow: View {
    let text: String

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(Colors.safeGreen)
                .font(.system(size: 14))
            Text(text)
                .font(Typography.caption)
                .foregroundColor(.white.opacity(0.9))
        }
    }
}

// MARK: - Twilio Setup View

struct TwilioSetupView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var alertService: AlertService

    @State private var accountSID = ""
    @State private var authToken = ""
    @State private var fromNumber = ""
    @State private var testMode = true
    @State private var isTesting = false
    @State private var testResult: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Mock/Test Mode", isOn: $testMode)
                } header: {
                    Text("Mode")
                } footer: {
                    Text(testMode ?
                         "Mock mode simulates Twilio API calls without sending real SMS. Perfect for testing." :
                         "Production mode sends real SMS via Twilio. Requires valid credentials and costs money.")
                }

                if !testMode {
                    Section {
                        TextField("Account SID", text: $accountSID)
                            .autocapitalization(.none)
                            .textContentType(.username)
                        SecureField("Auth Token", text: $authToken)
                        TextField("From Number", text: $fromNumber)
                            .keyboardType(.phonePad)
                    } header: {
                        Text("Twilio Credentials")
                    } footer: {
                        Text("Get these from twilio.com/console. From number must be a Twilio phone number you own.")
                    }
                } else {
                    Section {
                        TextField("Mock Account SID", text: $accountSID)
                            .autocapitalization(.none)
                        TextField("Mock From Number", text: $fromNumber)
                            .keyboardType(.phonePad)
                    } header: {
                        Text("Mock Configuration")
                    } footer: {
                        Text("Enter any values for testing. SMS will be simulated, not actually sent.")
                    }
                }

                Section {
                    Button {
                        testTwilioConfig()
                    } label: {
                        HStack {
                            if isTesting {
                                ProgressView()
                                    .padding(.trailing, 8)
                            }
                            Text(isTesting ? "Testing..." : "Test Configuration")
                        }
                    }
                    .disabled(fromNumber.isEmpty)

                    if let result = testResult {
                        HStack {
                            Image(systemName: result.contains("Success") ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(result.contains("Success") ? .green : .red)
                            Text(result)
                                .font(.caption)
                        }
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recent Send Logs")
                            .font(.headline)

                        if alertService.getTwilioLogs().isEmpty {
                            Text("No messages sent yet")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(alertService.getTwilioLogs().prefix(5)) { log in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(log.toNumber)
                                            .font(.caption)
                                        Text(log.messagePreview)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    if log.isMock {
                                        Text("MOCK")
                                            .font(.caption2)
                                            .padding(.horizontal, 4)
                                            .background(Color.blue.opacity(0.2))
                                            .cornerRadius(4)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Twilio SMS")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveTwilioConfig()
                    }
                    .disabled(fromNumber.isEmpty)
                }
            }
            .onAppear {
                loadExistingConfig()
            }
        }
    }

    private func loadExistingConfig() {
        if let config = alertService.twilioConfig {
            accountSID = config.accountSID
            fromNumber = config.fromNumber
            testMode = config.isTestMode
            // Don't load auth token for security
        }
    }

    private func testTwilioConfig() {
        isTesting = true
        testResult = nil

        Task {
            // Configure temporarily
            alertService.configureTwilio(
                accountSID: accountSID.isEmpty ? "MOCK_SID" : accountSID,
                authToken: authToken.isEmpty ? "MOCK_TOKEN" : authToken,
                fromNumber: fromNumber,
                testMode: testMode
            )

            do {
                let result = try await alertService.sendSMSViaTwilio(
                    to: "+15551234567", // Test number
                    message: "iWitness test message"
                )

                if result.success {
                    testResult = "Success! \(result.isMock ? "(Mock)" : "(Real)")"
                    alertService.logTwilioSend(result, message: "Test message")
                } else {
                    testResult = "Failed to send"
                }
            } catch {
                testResult = "Error: \(error.localizedDescription)"
            }

            isTesting = false
        }
    }

    private func saveTwilioConfig() {
        alertService.configureTwilio(
            accountSID: accountSID.isEmpty ? "MOCK_SID" : accountSID,
            authToken: authToken.isEmpty ? "MOCK_TOKEN" : authToken,
            fromNumber: fromNumber,
            testMode: testMode
        )
        dismiss()
    }
}

// MARK: - Safe PIN Setup View

struct SafePINSetupView: View {
    @Environment(\.dismiss) var dismiss

    @State private var pin1 = ""
    @State private var pin2 = ""
    @State private var showingError = false
    @State private var currentPIN: String

    init() {
        _currentPIN = State(initialValue: UserDefaults.standard.string(forKey: "safe_pin") ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "dial.medium.fill")
                            .font(.system(size: 48))
                            .foregroundColor(Colors.safeGreen)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical)

                        Text("Your Safe PIN protects the \"I'm Safe\" button during recording. Without the correct PIN, no one can stop your recording.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                Section {
                    SecureField("New PIN (4 digits)", text: $pin1)
                        .keyboardType(.numberPad)
                        .onChange(of: pin1) { _, newValue in
                            pin1 = String(newValue.filter { $0.isNumber }.prefix(4))
                        }

                    SecureField("Confirm PIN", text: $pin2)
                        .keyboardType(.numberPad)
                        .onChange(of: pin2) { _, newValue in
                            pin2 = String(newValue.filter { $0.isNumber }.prefix(4))
                        }
                } header: {
                    Text("Set Your PIN")
                } footer: {
                    if !currentPIN.isEmpty {
                        Text("Current PIN is set. Enter a new one to change it.")
                    } else {
                        Text("Default PIN is 1234. Set a custom PIN for security.")
                    }
                }

                Section {
                    Button {
                        savePIN()
                    } label: {
                        HStack {
                            Spacer()
                            Text("Save PIN")
                                .font(.headline)
                            Spacer()
                        }
                    }
                    .disabled(!isValidPIN)
                }
            }
            .navigationTitle("Safe PIN")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("PINs Don't Match", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Please make sure both PINs match.")
            }
        }
    }

    private var isValidPIN: Bool {
        pin1.count == 4 && pin1 == pin2
    }

    private func savePIN() {
        guard pin1 == pin2 else {
            showingError = true
            return
        }

        UserDefaults.standard.set(pin1, forKey: "safe_pin")

        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        dismiss()
    }
}

// MARK: - Duress PIN Setup View

struct DuressPINSetupView: View {
    @Environment(\.dismiss) var dismiss

    @State private var pin1 = ""
    @State private var pin2 = ""
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var currentPIN: String

    init() {
        _currentPIN = State(initialValue: UserDefaults.standard.string(forKey: "duress_pin") ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "exclamationmark.shield.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.orange)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical)

                        Text("Duress PIN silently sends an escalation alert instead of stopping the recording.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                Section {
                    SecureField("New PIN (4 digits)", text: $pin1)
                        .keyboardType(.numberPad)
                        .onChange(of: pin1) { _, newValue in
                            pin1 = String(newValue.filter { $0.isNumber }.prefix(4))
                        }

                    SecureField("Confirm PIN", text: $pin2)
                        .keyboardType(.numberPad)
                        .onChange(of: pin2) { _, newValue in
                            pin2 = String(newValue.filter { $0.isNumber }.prefix(4))
                        }
                } header: {
                    Text("Set Duress PIN")
                } footer: {
                    if !currentPIN.isEmpty {
                        Text("Duress PIN is set. Enter a new one to change it.")
                    } else {
                        Text("Choose a PIN different from your Safe PIN.")
                    }
                }

                Section {
                    Button {
                        savePIN()
                    } label: {
                        HStack { Spacer(); Text("Save PIN").font(.headline); Spacer() }
                    }
                    .disabled(!isValidPIN)
                }
            }
            .navigationTitle("Duress PIN")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .alert("\(errorMessage)", isPresented: $showingError) { Button("OK", role: .cancel) { } }
        }
    }

    private var isValidPIN: Bool { pin1.count == 4 && pin1 == pin2 }

    private func savePIN() {
        guard pin1 == pin2 else {
            errorMessage = "PINs Don't Match"; showingError = true; return
        }
        let safe = UserDefaults.standard.string(forKey: "safe_pin") ?? "1234"
        if pin1 == safe { errorMessage = "Duress PIN must differ from Safe PIN"; showingError = true; return }

        UserDefaults.standard.set(pin1, forKey: "duress_pin")

        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        dismiss()
    }
}

// MARK: - Streaming Setup View

struct StreamingSetupView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var liveStreamService: LiveStreamService

    @State private var selectedDestination = 0 // 0 = Use existing backup, 1 = Cloudflare, 2 = Custom
    @State private var r2AccountID = ""
    @State private var r2BucketName = ""
    @State private var r2AccessKey = ""
    @State private var r2SecretKey = ""
    @State private var customServerURL = ""
    @State private var customUsername = ""
    @State private var customPassword = ""
    @State private var nasExternalURL = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.system(size: 48))
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical)

                        Text("Live streaming sends video in real-time to cloud storage. Your contacts can watch as it happens.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                Section {
                    Picker("Stream Destination", selection: $selectedDestination) {
                        Text("Use Existing Backup").tag(0)
                        Text("Cloudflare R2").tag(1)
                        Text("Custom Server").tag(2)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Destination")
                }

                if selectedDestination == 0 {
                    // Use existing backup destination
                    Section {
                        Text("Streams will be saved to your configured backup destination (NAS or Cloud).")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        if UserDefaults.standard.string(forKey: "nas_url") != nil {
                            TextField("External Access URL (optional)", text: $nasExternalURL)
                                .keyboardType(.URL)
                                .autocapitalization(.none)
                        }
                    } header: {
                        Text("Settings")
                    } footer: {
                        Text("If your NAS is accessible externally, enter the public URL so contacts can view the stream.")
                    }
                }

                if selectedDestination == 1 {
                    // Cloudflare R2
                    Section {
                        TextField("Account ID", text: $r2AccountID)
                            .autocapitalization(.none)
                        TextField("Bucket Name", text: $r2BucketName)
                            .autocapitalization(.none)
                        TextField("Access Key ID", text: $r2AccessKey)
                            .autocapitalization(.none)
                        SecureField("Secret Access Key", text: $r2SecretKey)
                    } header: {
                        Text("Cloudflare R2")
                    } footer: {
                        Text("Create an R2 bucket at dash.cloudflare.com. Enable public access for live viewing.")
                    }
                }

                if selectedDestination == 2 {
                    // Custom server
                    Section {
                        TextField("Server URL", text: $customServerURL)
                            .keyboardType(.URL)
                            .autocapitalization(.none)
                        TextField("Username (optional)", text: $customUsername)
                            .autocapitalization(.none)
                        SecureField("Password (optional)", text: $customPassword)
                    } header: {
                        Text("Custom Server")
                    } footer: {
                        Text("Any WebDAV-compatible server. Must be publicly accessible for contacts to view.")
                    }
                }

                Section {
                    Button {
                        saveConfiguration()
                    } label: {
                        HStack {
                            Spacer()
                            Text("Save Configuration")
                                .font(.headline)
                            Spacer()
                        }
                    }
                    .disabled(!canSave)
                }
            }
            .navigationTitle("Live Streaming")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                loadExistingConfig()
            }
        }
    }

    private var canSave: Bool {
        switch selectedDestination {
        case 0:
            return UserDefaults.standard.string(forKey: "nas_url") != nil ||
                   UserDefaults.standard.string(forKey: "cloud_access_key") != nil
        case 1:
            return !r2AccountID.isEmpty && !r2BucketName.isEmpty &&
                   !r2AccessKey.isEmpty && !r2SecretKey.isEmpty
        case 2:
            return !customServerURL.isEmpty
        default:
            return false
        }
    }

    private func loadExistingConfig() {
        nasExternalURL = UserDefaults.standard.string(forKey: "nas_external_url") ?? ""
    }

    private func saveConfiguration() {
        switch selectedDestination {
        case 0:
            // Use existing backup
            if !nasExternalURL.isEmpty {
                UserDefaults.standard.set(nasExternalURL, forKey: "nas_external_url")
            }
            UserDefaults.standard.set("existing", forKey: "stream_destination")

        case 1:
            // Cloudflare R2
            liveStreamService.configureCloudflareR2(
                accountID: r2AccountID,
                bucketName: r2BucketName,
                accessKey: r2AccessKey,
                secretKey: r2SecretKey
            )
            UserDefaults.standard.set(r2AccountID, forKey: "stream_r2_account")
            UserDefaults.standard.set(r2BucketName, forKey: "stream_r2_bucket")
            UserDefaults.standard.set(r2AccessKey, forKey: "stream_r2_access_key")
            UserDefaults.standard.set(r2SecretKey, forKey: "stream_r2_secret_key")
            UserDefaults.standard.set("cloudflare", forKey: "stream_destination")

        case 2:
            // Custom server
            if let url = URL(string: customServerURL) {
                liveStreamService.configureCustomServer(
                    url: url,
                    username: customUsername.isEmpty ? nil : customUsername,
                    password: customPassword.isEmpty ? nil : customPassword
                )
            }
            UserDefaults.standard.set(customServerURL, forKey: "stream_custom_url")
            UserDefaults.standard.set(customUsername, forKey: "stream_custom_username")
            UserDefaults.standard.set(customPassword, forKey: "stream_custom_password")
            UserDefaults.standard.set("custom", forKey: "stream_destination")

        default:
            break
        }

        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        dismiss()
    }
}

#Preview {
    SettingsView()
        .environmentObject(AlertService())
        .environmentObject(UploadService())
        .environmentObject(LiveStreamService())
}
