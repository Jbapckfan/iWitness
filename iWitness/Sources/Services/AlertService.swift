import Foundation
import UserNotifications
#if canImport(MessageUI)
import MessageUI
#endif

/// Manages emergency alerts to contacts via SMS, email, and push
@MainActor
class AlertService: ObservableObject {
    // MARK: - Published State

    @Published var contacts: [EmergencyContact] = []
    @Published var alertsSent: Int = 0
    @Published var alertsConfirmed: Int = 0
    @Published var lastAlertTime: Date?
    @Published var alertError: AlertError?

    // MARK: - Twilio Configuration

    @Published var twilioConfig: TwilioConfig?
    @Published var useTwilio: Bool = false
    @Published var twilioStatus: TwilioStatus = .notConfigured

    enum TwilioStatus: String {
        case notConfigured = "Not Configured"
        case configured = "Configured"
        case sending = "Sending..."
        case success = "Sent"
        case failed = "Failed"
        case mockMode = "Mock Mode"
    }

    struct TwilioConfig: Codable {
        var accountSID: String
        var authToken: String
        var fromNumber: String
        var isTestMode: Bool // For mock/sandbox testing

        var isValid: Bool {
            !accountSID.isEmpty && !authToken.isEmpty && !fromNumber.isEmpty
        }
    }

    // MARK: - Configuration

    private var streamURL: String?
    private var currentIncidentID: String?

    // MARK: - Errors

    enum AlertError: LocalizedError {
        case noContacts
        case smsNotAvailable
        case sendFailed(String)

        var errorDescription: String? {
            switch self {
            case .noContacts:
                return "No emergency contacts configured"
            case .smsNotAvailable:
                return "SMS is not available on this device"
            case .sendFailed(let reason):
                return "Failed to send alert: \(reason)"
            }
        }
    }

    // MARK: - Contact Model

    struct EmergencyContact: Codable, Identifiable {
        let id: UUID
        var name: String
        var phone: String
        var email: String?
        var isLawyer: Bool
        var notifyViaSMS: Bool
        var notifyViaEmail: Bool
        var priority: Int // 1 = primary, 2 = secondary, etc.

        // For display privacy during recording
        var displayName: String {
            "Contact \(priority)"
        }

        init(name: String, phone: String, email: String? = nil, isLawyer: Bool = false, priority: Int = 1) {
            self.id = UUID()
            self.name = name
            self.phone = phone
            self.email = email
            self.isLawyer = isLawyer
            self.notifyViaSMS = true
            self.notifyViaEmail = email != nil
            self.priority = priority
        }
    }

    // MARK: - Initialization

    func configure() {
        loadContacts()
    }

    // MARK: - Permissions

    func requestNotificationPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()

        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            print("[iWitness] Notification permission error: \(error)")
            return false
        }
    }

    // MARK: - Contact Management

    func addContact(_ contact: EmergencyContact) {
        contacts.append(contact)
        saveContacts()
    }

    func removeContact(_ contact: EmergencyContact) {
        contacts.removeAll { $0.id == contact.id }
        saveContacts()
    }

    func updateContact(_ contact: EmergencyContact) {
        if let index = contacts.firstIndex(where: { $0.id == contact.id }) {
            contacts[index] = contact
            saveContacts()
        }
    }

    private func loadContacts() {
        if let data = UserDefaults.standard.data(forKey: "emergency_contacts"),
           let decoded = try? JSONDecoder().decode([EmergencyContact].self, from: data) {
            contacts = decoded
        }
    }

    private func saveContacts() {
        if let encoded = try? JSONEncoder().encode(contacts) {
            UserDefaults.standard.set(encoded, forKey: "emergency_contacts")
        }
    }

    // MARK: - Alert Dispatch

    /// Sends emergency alerts to all configured contacts
    func sendEmergencyAlert(incidentID: String, location: Location?, streamURL: String?) async {
        guard !contacts.isEmpty else {
            alertError = .noContacts
            return
        }

        self.currentIncidentID = incidentID
        self.streamURL = streamURL
        self.lastAlertTime = Date()
        alertsSent = 0
        alertsConfirmed = 0

        // Get address if location available
        var address: String?
        if let location = location {
            address = await LocationService().getAddress(for: location)
        }

        // Send to all contacts
        for contact in contacts.sorted(by: { $0.priority < $1.priority }) {
            // SMS
            if contact.notifyViaSMS {
                let success = await sendSMS(to: contact, location: location, address: address)
                if success { alertsSent += 1 }
            }

            // Email
            if contact.notifyViaEmail, let email = contact.email {
                await sendEmail(to: email, contact: contact, location: location, address: address)
                alertsSent += 1
            }
        }
    }

    // MARK: - SMS

    private func sendSMS(to contact: EmergencyContact, location: Location?, address: String?) async -> Bool {
        let message = formatAlertMessage(location: location, address: address)

        // Use URL scheme for SMS (this will prompt user)
        // For background sending, would need to integrate with Twilio or similar
        let smsURL = "sms:\(contact.phone)&body=\(message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"

        guard let url = URL(string: smsURL) else { return false }

        #if os(iOS)
        await MainActor.run {
            UIApplication.shared.open(url)
        }
        return true
        #else
        return false
        #endif
    }

    private func formatAlertMessage(location: Location?, address: String?) -> String {
        var message = """
        🚨 WITNESS ALERT

        iWitness mode activated.
        """

        if let address = address {
            message += "\n📍 \(address)"
        }

        if let location = location {
            message += "\n🗺️ https://maps.google.com/?q=\(location.latitude),\(location.longitude)"
        }

        if let streamURL = streamURL {
            message += "\n🔴 LIVE: \(streamURL)"
        }

        message += "\n\nTime: \(DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium))"
        message += "\n\nReply SAFE to confirm received."

        return message
    }

    // MARK: - Email

    private func sendEmail(to email: String, contact: EmergencyContact, location: Location?, address: String?) async {
        // Email would typically go through a backend service
        // For MVP, we'll compose an email URL

        let subject = "🚨 iWitness Emergency Alert"
        let body = formatEmailBody(location: location, address: address)

        let emailURL = "mailto:\(email)?subject=\(subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&body=\(body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"

        guard let url = URL(string: emailURL) else { return }

        #if os(iOS)
        await MainActor.run {
            UIApplication.shared.open(url)
        }
        #endif
    }

    private func formatEmailBody(location: Location?, address: String?) -> String {
        var body = """
        WITNESS ALERT

        iWitness emergency recording has been activated.

        INCIDENT ID: \(currentIncidentID ?? "Unknown")
        TIME: \(ISO8601DateFormatter().string(from: Date()))

        """

        if let address = address {
            body += """
            ADDRESS: \(address)

            """
        }

        if let location = location {
            body += """
            GPS COORDINATES: \(location.coordinate)
            MAP LINK: https://maps.google.com/?q=\(location.latitude),\(location.longitude)

            """
        }

        if let streamURL = streamURL {
            body += """
            LIVE STREAM: \(streamURL)

            """
        }

        body += """

        ---
        This is an automated alert from iWitness.
        Please check on the sender immediately.
        """

        return body
    }

    // MARK: - Escalation

    /// Sends follow-up alerts if no confirmation received
    func escalateAlert(incidentID: String) async {
        guard incidentID == currentIncidentID else { return }

        // Re-send with escalation flag
        for contact in contacts where contact.isLawyer {
            let message = """
            ⚠️ ESCALATION - NO RESPONSE

            Previous iWitness alert was not confirmed.
            Incident ID: \(incidentID)

            IMMEDIATE ATTENTION REQUIRED
            """

            // Send escalated SMS
            let smsURL = "sms:\(contact.phone)&body=\(message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
            if let url = URL(string: smsURL) {
                #if os(iOS)
                await MainActor.run {
                    UIApplication.shared.open(url)
                }
                #endif
            }
        }
    }

    // MARK: - Confirmation

    func confirmReceived(from contact: EmergencyContact) {
        alertsConfirmed += 1
    }

    // MARK: - Safe Signal

    func sendSafeSignal() async {
        let message = """
        ✅ SAFE

        iWitness recording has ended.
        User has indicated they are safe.

        Incident ID: \(currentIncidentID ?? "Unknown")
        End time: \(DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium))
        """

        for contact in contacts {
            if contact.notifyViaSMS {
                let smsURL = "sms:\(contact.phone)&body=\(message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
                if let url = URL(string: smsURL) {
                    #if os(iOS)
                    await MainActor.run {
                        UIApplication.shared.open(url)
                    }
                    #endif
                }
            }
        }
    }
}

// MARK: - Twilio Integration

extension AlertService {
    /// Configure Twilio for background SMS sending
    func configureTwilio(accountSID: String, authToken: String, fromNumber: String, testMode: Bool = true) {
        let config = TwilioConfig(
            accountSID: accountSID,
            authToken: authToken,
            fromNumber: fromNumber,
            isTestMode: testMode
        )
        self.twilioConfig = config
        self.useTwilio = true
        self.twilioStatus = testMode ? .mockMode : .configured

        // Save to UserDefaults (in production, use Keychain for auth token)
        if let encoded = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(encoded, forKey: "twilio_config")
        }
        UserDefaults.standard.set(true, forKey: "use_twilio")
    }

    /// Load saved Twilio configuration
    func loadTwilioConfig() {
        if let data = UserDefaults.standard.data(forKey: "twilio_config"),
           let config = try? JSONDecoder().decode(TwilioConfig.self, from: data) {
            self.twilioConfig = config
            self.useTwilio = UserDefaults.standard.bool(forKey: "use_twilio")
            self.twilioStatus = config.isTestMode ? .mockMode : .configured
        }
    }

    /// Send SMS via Twilio API (or mock in test mode)
    func sendSMSViaTwilio(to phone: String, message: String) async throws -> TwilioSendResult {
        guard let config = twilioConfig, config.isValid else {
            throw AlertError.sendFailed("Twilio not configured")
        }

        twilioStatus = .sending

        // In test/mock mode, simulate the API call
        if config.isTestMode {
            return await mockTwilioSend(to: phone, message: message, config: config)
        }

        // Real Twilio API call
        return try await realTwilioSend(to: phone, message: message, config: config)
    }

    /// Mock Twilio send for testing
    private func mockTwilioSend(to phone: String, message: String, config: TwilioConfig) async -> TwilioSendResult {
        // Simulate network delay
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

        let result = TwilioSendResult(
            success: true,
            messageID: "MOCK_\(UUID().uuidString.prefix(8))",
            timestamp: Date(),
            toNumber: phone,
            fromNumber: config.fromNumber,
            status: "queued",
            isMock: true
        )

        print("[iWitness] MOCK Twilio SMS sent to \(phone)")
        print("[iWitness] Message: \(message.prefix(50))...")

        twilioStatus = .mockMode
        return result
    }

    /// Real Twilio API call
    private func realTwilioSend(to phone: String, message: String, config: TwilioConfig) async throws -> TwilioSendResult {
        let url = URL(string: "https://api.twilio.com/2010-04-01/Accounts/\(config.accountSID)/Messages.json")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let credentials = "\(config.accountSID):\(config.authToken)".data(using: .utf8)!.base64EncodedString()
        request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var bodyComponents = URLComponents()
        bodyComponents.queryItems = [
            URLQueryItem(name: "To", value: phone),
            URLQueryItem(name: "From", value: config.fromNumber),
            URLQueryItem(name: "Body", value: message)
        ]
        request.httpBody = bodyComponents.query?.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            twilioStatus = .failed
            throw AlertError.sendFailed("Invalid response")
        }

        if (200...299).contains(httpResponse.statusCode) {
            // Parse response
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let result = TwilioSendResult(
                    success: true,
                    messageID: json["sid"] as? String ?? "unknown",
                    timestamp: Date(),
                    toNumber: phone,
                    fromNumber: config.fromNumber,
                    status: json["status"] as? String ?? "sent",
                    isMock: false
                )
                twilioStatus = .success
                return result
            }
            twilioStatus = .success
            return TwilioSendResult(success: true, messageID: "unknown", timestamp: Date(), toNumber: phone, fromNumber: config.fromNumber, status: "sent", isMock: false)
        } else {
            twilioStatus = .failed
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AlertError.sendFailed("Twilio error: \(errorMessage)")
        }
    }

    /// Send emergency alert via Twilio (background, no user interaction)
    func sendEmergencyAlertViaTwilio(incidentID: String, location: Location?) async {
        guard useTwilio, let _ = twilioConfig else {
            // Fall back to SMS URL scheme
            await sendEmergencyAlert(incidentID: incidentID, location: location, streamURL: nil)
            return
        }

        self.currentIncidentID = incidentID
        self.lastAlertTime = Date()
        alertsSent = 0

        // Get address if location available
        var address: String?
        if let location = location {
            address = await LocationService().getAddress(for: location)
        }

        let message = formatAlertMessage(location: location, address: address)

        // Send to all contacts via Twilio
        for contact in contacts.sorted(by: { $0.priority < $1.priority }) {
            if contact.notifyViaSMS {
                do {
                    let result = try await sendSMSViaTwilio(to: contact.phone, message: message)
                    if result.success {
                        alertsSent += 1
                        print("[iWitness] Alert sent to \(contact.displayName): \(result.messageID)")
                    }
                } catch {
                    print("[iWitness] Failed to send alert to \(contact.displayName): \(error)")
                }
            }
        }
    }
}

// MARK: - Twilio Result Model

struct TwilioSendResult {
    let success: Bool
    let messageID: String
    let timestamp: Date
    let toNumber: String
    let fromNumber: String
    let status: String
    let isMock: Bool
}

// MARK: - Twilio Logs (for debugging)

extension AlertService {
    struct TwilioLogEntry: Identifiable, Codable {
        let id: UUID
        let timestamp: Date
        let toNumber: String
        let status: String
        let messagePreview: String
        let isMock: Bool

        init(result: TwilioSendResult, messagePreview: String) {
            self.id = UUID()
            self.timestamp = result.timestamp
            self.toNumber = result.toNumber
            self.status = result.status
            self.messagePreview = String(messagePreview.prefix(50))
            self.isMock = result.isMock
        }
    }

    /// Get recent Twilio send logs
    func getTwilioLogs() -> [TwilioLogEntry] {
        guard let data = UserDefaults.standard.data(forKey: "twilio_logs"),
              let logs = try? JSONDecoder().decode([TwilioLogEntry].self, from: data) else {
            return []
        }
        return logs
    }

    /// Add entry to Twilio logs
    func logTwilioSend(_ result: TwilioSendResult, message: String) {
        var logs = getTwilioLogs()
        let entry = TwilioLogEntry(result: result, messagePreview: message)
        logs.insert(entry, at: 0)

        // Keep only last 50 entries
        if logs.count > 50 {
            logs = Array(logs.prefix(50))
        }

        if let encoded = try? JSONEncoder().encode(logs) {
            UserDefaults.standard.set(encoded, forKey: "twilio_logs")
        }
    }
}
