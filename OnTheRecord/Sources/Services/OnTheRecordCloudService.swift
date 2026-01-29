import Foundation

/// Manages OnTheRecord Cloud storage service - a managed cloud backup for users without NAS
@MainActor
class OnTheRecordCloudService: ObservableObject {
    
    static let shared = OnTheRecordCloudService()
    
    // MARK: - Configuration
    
    /// Your Cloudflare Worker endpoint for upload proxy
    private let apiEndpoint = "https://ontherecord-cloud.your-domain.workers.dev"
    
    // MARK: - Published State
    
    @Published var isConfigured: Bool = false
    @Published var isAuthenticated: Bool = false
    @Published var storageUsed: Int64 = 0          // bytes
    @Published var storageLimit: Int64 = 0          // bytes
    @Published var uploadInProgress: Bool = false
    
    // MARK: - Credentials
    
    private var userID: String?
    private var apiToken: String?
    
    // MARK: - Initialization
    
    init() {
        loadCredentials()
    }
    
    // MARK: - Authentication
    
    /// Register new user with OnTheRecord Cloud
    func register(email: String) async throws -> Bool {
        let url = URL(string: "\(apiEndpoint)/register")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["email": email]
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw CloudError.registrationFailed
        }
        
        // Parse response
        let result = try JSONDecoder().decode(RegistrationResponse.self, from: data)
        
        // Save credentials
        userID = result.userID
        apiToken = result.apiToken
        saveCredentials()
        
        isAuthenticated = true
        isConfigured = true
        storageLimit = result.storageLimitBytes
        
        return true
    }
    
    /// Login existing user
    func login(email: String, token: String) async throws -> Bool {
        let url = URL(string: "\(apiEndpoint)/login")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["email": email, "token": token]
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw CloudError.loginFailed
        }
        
        let result = try JSONDecoder().decode(LoginResponse.self, from: data)
        
        userID = result.userID
        apiToken = result.apiToken
        saveCredentials()
        
        isAuthenticated = true
        isConfigured = true
        storageUsed = result.storageUsedBytes
        storageLimit = result.storageLimitBytes
        
        return true
    }
    
    // MARK: - Upload
    
    /// Upload encrypted video chunk to OnTheRecord Cloud
    func uploadChunk(data: Data, filename: String, incidentID: String) async throws {
        guard let token = apiToken, let userID = userID else {
            throw CloudError.notAuthenticated
        }
        
        uploadInProgress = true
        defer { uploadInProgress = false }
        
        let url = URL(string: "\(apiEndpoint)/upload")!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue(userID, forHTTPHeaderField: "X-User-ID")
        request.setValue(incidentID, forHTTPHeaderField: "X-Incident-ID")
        request.setValue(filename, forHTTPHeaderField: "X-Filename")
        request.httpBody = data
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw CloudError.uploadFailed
        }
        
        // Update storage used
        storageUsed += Int64(data.count)
    }
    
    /// Generate signed URL for viewing a recording
    func getViewURL(incidentID: String, filename: String) async throws -> URL {
        guard let token = apiToken else {
            throw CloudError.notAuthenticated
        }
        
        let url = URL(string: "\(apiEndpoint)/signed-url?incident=\(incidentID)&file=\(filename)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw CloudError.urlGenerationFailed
        }
        
        let result = try JSONDecoder().decode(SignedURLResponse.self, from: data)
        
        guard let signedURL = URL(string: result.url) else {
            throw CloudError.urlGenerationFailed
        }
        
        return signedURL
    }
    
    /// List all recordings in cloud storage
    func listRecordings() async throws -> [CloudRecording] {
        guard let token = apiToken else {
            throw CloudError.notAuthenticated
        }
        
        let url = URL(string: "\(apiEndpoint)/recordings")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw CloudError.listFailed
        }
        
        let result = try JSONDecoder().decode(RecordingsResponse.self, from: data)
        return result.recordings
    }
    
    // MARK: - Credential Storage
    
    private func saveCredentials() {
        if let userID = userID {
            _ = KeychainHelper.shared.save(service: "OnTheRecord", account: "cloud_user_id", value: userID)
        }
        if let token = apiToken {
            _ = KeychainHelper.shared.save(service: "OnTheRecord", account: "cloud_api_token", value: token)
        }
    }
    
    private func loadCredentials() {
        userID = KeychainHelper.shared.read(service: "OnTheRecord", account: "cloud_user_id")
        apiToken = KeychainHelper.shared.read(service: "OnTheRecord", account: "cloud_api_token")
        
        isConfigured = userID != nil && apiToken != nil
        isAuthenticated = isConfigured
    }
    
    func logout() {
        userID = nil
        apiToken = nil
        KeychainHelper.shared.delete(service: "OnTheRecord", account: "cloud_user_id")
        KeychainHelper.shared.delete(service: "OnTheRecord", account: "cloud_api_token")
        isConfigured = false
        isAuthenticated = false
        storageUsed = 0
        storageLimit = 0
    }
    
    // MARK: - Data Models
    
    struct RegistrationResponse: Codable {
        let userID: String
        let apiToken: String
        let storageLimitBytes: Int64
    }
    
    struct LoginResponse: Codable {
        let userID: String
        let apiToken: String
        let storageUsedBytes: Int64
        let storageLimitBytes: Int64
    }
    
    struct SignedURLResponse: Codable {
        let url: String
        let expiresIn: Int
    }
    
    struct RecordingsResponse: Codable {
        let recordings: [CloudRecording]
    }
    
    struct CloudRecording: Codable, Identifiable {
        let id: String
        let incidentID: String
        let filename: String
        let sizeBytes: Int64
        let createdAt: Date
    }
    
    // MARK: - Errors
    
    enum CloudError: LocalizedError {
        case notAuthenticated
        case registrationFailed
        case loginFailed
        case uploadFailed
        case urlGenerationFailed
        case listFailed
        case storageLimitExceeded
        
        var errorDescription: String? {
            switch self {
            case .notAuthenticated:
                return "Not logged in to OnTheRecord Cloud"
            case .registrationFailed:
                return "Failed to create account"
            case .loginFailed:
                return "Login failed - check your credentials"
            case .uploadFailed:
                return "Failed to upload to cloud"
            case .urlGenerationFailed:
                return "Failed to generate viewing URL"
            case .listFailed:
                return "Failed to list recordings"
            case .storageLimitExceeded:
                return "Storage limit exceeded - upgrade your plan"
            }
        }
    }
}

// MARK: - Storage Formatting

extension OnTheRecordCloudService {
    var storageUsedFormatted: String {
        ByteCountFormatter.string(fromByteCount: storageUsed, countStyle: .file)
    }
    
    var storageLimitFormatted: String {
        ByteCountFormatter.string(fromByteCount: storageLimit, countStyle: .file)
    }
    
    var storagePercentage: Double {
        guard storageLimit > 0 else { return 0 }
        return Double(storageUsed) / Double(storageLimit)
    }
}
