import Foundation
import Network
import CryptoKit

/// Manages upload queue and multi-destination chunk transmission
@MainActor
class UploadService: ObservableObject {
    // MARK: - Published State

    @Published var queueDepth: Int = 0
    @Published var chunksUploaded: Int = 0
    @Published var uploadSpeed: Double = 0 // bytes per second
    @Published var isUploading: Bool = false
    @Published var currentDestination: String = ""
    @Published var lastError: UploadError?

    // MARK: - Configuration

    struct UploadDestination {
        let name: String
        let type: DestinationType
        let url: URL
        let credentials: UploadCredentials?
        let priority: Int // Lower = higher priority

        enum DestinationType {
            case webdav
            case sftp
            case s3Compatible // Cloudflare R2, Backblaze B2
            case local
        }
    }

    struct UploadCredentials {
        let username: String?
        let password: String?
        let apiKey: String?
        let secretKey: String?
    }

    // MARK: - State

    private var destinations: [UploadDestination] = []
    private var uploadQueue: [QueuedChunk] = []
    private var uploadTask: Task<Void, Never>?
    private let networkMonitor = NWPathMonitor()
    private var isNetworkAvailable = true

    // Upload statistics
    private var bytesUploaded: Int64 = 0
    private var uploadStartTime: Date?

    // MARK: - Queue Item

    private struct QueuedChunk {
        let chunk: EncryptedChunk
        let incidentID: String
        let addedAt: Date
        var uploadAttempts: Int = 0
        var uploadedTo: Set<String> = []
    }

    // MARK: - Errors

    enum UploadError: LocalizedError {
        case noDestinations
        case networkUnavailable
        case authenticationFailed
        case uploadFailed(String)
        case allDestinationsFailed

        var errorDescription: String? {
            switch self {
            case .noDestinations:
                return "No upload destinations configured"
            case .networkUnavailable:
                return "Network is unavailable"
            case .authenticationFailed:
                return "Authentication failed"
            case .uploadFailed(let reason):
                return "Upload failed: \(reason)"
            case .allDestinationsFailed:
                return "All upload destinations failed"
            }
        }
    }

    // MARK: - Initialization

    init() {
        setupNetworkMonitor()
    }

    private func setupNetworkMonitor() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isNetworkAvailable = path.status == .satisfied
                if path.status == .satisfied {
                    self?.resumeUploads()
                }
            }
        }
        networkMonitor.start(queue: DispatchQueue.global(qos: .utility))
    }

    // MARK: - Configuration

    func configureDestinations(_ destinations: [UploadDestination]) {
        self.destinations = destinations.sorted { $0.priority < $1.priority }
    }

    /// Convenience method to add NAS destination
    func addNASDestination(url: URL, username: String, password: String) {
        let destination = UploadDestination(
            name: "NAS",
            type: .webdav,
            url: url,
            credentials: UploadCredentials(username: username, password: password, apiKey: nil, secretKey: nil),
            priority: 1
        )
        destinations.append(destination)
        destinations.sort { $0.priority < $1.priority }
    }

    /// Convenience method to add Cloudflare R2 destination
    func addR2Destination(accountID: String, bucketName: String, accessKeyID: String, secretAccessKey: String) {
        let url = URL(string: "https://\(accountID).r2.cloudflarestorage.com/\(bucketName)")!
        let destination = UploadDestination(
            name: "Cloudflare R2",
            type: .s3Compatible,
            url: url,
            credentials: UploadCredentials(username: nil, password: nil, apiKey: accessKeyID, secretKey: secretAccessKey),
            priority: 2
        )
        destinations.append(destination)
        destinations.sort { $0.priority < $1.priority }
    }

    // MARK: - Queue Management

    func queueChunk(_ chunk: EncryptedChunk) {
        let queuedChunk = QueuedChunk(
            chunk: chunk,
            incidentID: chunk.header.incidentID,
            addedAt: Date()
        )

        uploadQueue.append(queuedChunk)
        queueDepth = uploadQueue.count

        // Start upload if not already running
        if uploadTask == nil {
            startUploadLoop()
        }
    }

    // MARK: - Upload Loop

    private func startUploadLoop() {
        uploadTask = Task {
            isUploading = true
            uploadStartTime = Date()

            while !uploadQueue.isEmpty && !Task.isCancelled {
                // Get oldest chunk (FIFO, but could prioritize newest for survival)
                guard var chunk = uploadQueue.first else { break }

                // Try each destination
                var uploadedToAny = false
                for destination in destinations {
                    // Skip if already uploaded to this destination
                    if chunk.uploadedTo.contains(destination.name) { continue }

                    do {
                        currentDestination = destination.name
                        try await uploadChunk(chunk.chunk, to: destination)
                        chunk.uploadedTo.insert(destination.name)
                        uploadedToAny = true
                        chunksUploaded += 1

                        // Update speed calculation
                        updateUploadSpeed(chunkSize: chunk.chunk.serialize().count)
                    } catch {
                        print("[iWitness] Upload to \(destination.name) failed: \(error)")
                        chunk.uploadAttempts += 1
                    }
                }

                if uploadedToAny {
                    // Remove from queue if uploaded to at least one destination
                    uploadQueue.removeFirst()
                } else {
                    // Move to back of queue for retry
                    uploadQueue.removeFirst()
                    if chunk.uploadAttempts < 5 {
                        uploadQueue.append(chunk)
                    } else {
                        lastError = .allDestinationsFailed
                    }
                }

                queueDepth = uploadQueue.count

                // Small delay between chunks to prevent overwhelming
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }

            isUploading = false
            uploadTask = nil
        }
    }

    private func resumeUploads() {
        guard uploadTask == nil && !uploadQueue.isEmpty else { return }
        startUploadLoop()
    }

    private func updateUploadSpeed(chunkSize: Int) {
        bytesUploaded += Int64(chunkSize)
        if let startTime = uploadStartTime {
            let elapsed = Date().timeIntervalSince(startTime)
            uploadSpeed = Double(bytesUploaded) / elapsed
        }
    }

    // MARK: - Upload Methods

    private func uploadChunk(_ chunk: EncryptedChunk, to destination: UploadDestination) async throws {
        switch destination.type {
        case .webdav:
            try await uploadViaWebDAV(chunk, to: destination)
        case .sftp:
            try await uploadViaSFTP(chunk, to: destination)
        case .s3Compatible:
            try await uploadViaS3(chunk, to: destination)
        case .local:
            try await saveLocally(chunk, to: destination)
        }
    }

    // MARK: - WebDAV Upload (for NAS)

    private func uploadViaWebDAV(_ chunk: EncryptedChunk, to destination: UploadDestination) async throws {
        let filename = "iWitness/\(chunk.header.incidentID)/chunk_\(String(format: "%05d", chunk.header.chunkNumber)).iwc"
        let uploadURL = destination.url.appendingPathComponent(filename)

        var request = URLRequest(url: uploadURL)
        request.httpMethod = "PUT"
        request.httpBody = chunk.serialize()
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

        // Add basic auth if credentials provided
        if let creds = destination.credentials,
           let username = creds.username,
           let password = creds.password {
            let authString = "\(username):\(password)"
            if let authData = authString.data(using: .utf8) {
                let base64Auth = authData.base64EncodedString()
                request.setValue("Basic \(base64Auth)", forHTTPHeaderField: "Authorization")
            }
        }

        // Create directory hierarchy: iWitness/{incidentID}/
        try await createWebDAVDirectory(destination.url.appendingPathComponent("iWitness"), credentials: destination.credentials)
        try await createWebDAVDirectory(destination.url.appendingPathComponent("iWitness/\(chunk.header.incidentID)"), credentials: destination.credentials)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw UploadError.uploadFailed("WebDAV upload failed")
        }
    }

    private func createWebDAVDirectory(_ url: URL, credentials: UploadCredentials?) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "MKCOL"

        if let creds = credentials,
           let username = creds.username,
           let password = creds.password {
            let authString = "\(username):\(password)"
            if let authData = authString.data(using: .utf8) {
                let base64Auth = authData.base64EncodedString()
                request.setValue("Basic \(base64Auth)", forHTTPHeaderField: "Authorization")
            }
        }

        // Ignore errors - directory might already exist
        _ = try? await URLSession.shared.data(for: request)
    }

    // MARK: - S3 Compatible Upload (Cloudflare R2)

    private func uploadViaS3(_ chunk: EncryptedChunk, to destination: UploadDestination) async throws {
        guard let creds = destination.credentials,
              let accessKey = creds.apiKey,
              let secretKey = creds.secretKey else {
            throw UploadError.authenticationFailed
        }

        let key = "\(chunk.header.incidentID)/chunk_\(String(format: "%05d", chunk.header.chunkNumber)).iwc"
        let body = chunk.serialize()

        // Create signed request using AWS Signature V4
        let request = try createSignedS3Request(
            url: destination.url.appendingPathComponent(key),
            method: "PUT",
            body: body,
            accessKey: accessKey,
            secretKey: secretKey
        )

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw UploadError.uploadFailed("S3 upload failed")
        }
    }

    private func createSignedS3Request(url: URL, method: String, body: Data, accessKey: String, secretKey: String) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body

        let date = ISO8601DateFormatter().string(from: Date())
        let contentHash = sha256Hash(body)

        request.setValue(date, forHTTPHeaderField: "x-amz-date")
        request.setValue(contentHash, forHTTPHeaderField: "x-amz-content-sha256")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue("\(body.count)", forHTTPHeaderField: "Content-Length")

        // Simplified signing - in production, use proper AWS SigV4
        // For now, R2 also supports simpler auth methods
        let signature = computeS3Signature(request: request, secretKey: secretKey)
        request.setValue("AWS4-HMAC-SHA256 Credential=\(accessKey)/...,SignedHeaders=...,Signature=\(signature)", forHTTPHeaderField: "Authorization")

        return request
    }

    private func sha256Hash(_ data: Data) -> String {
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    private func computeS3Signature(request: URLRequest, secretKey: String) -> String {
        // Simplified - production would implement full AWS SigV4
        return "placeholder"
    }

    // MARK: - SFTP Upload

    private func uploadViaSFTP(_ chunk: EncryptedChunk, to destination: UploadDestination) async throws {
        // SFTP would require a third-party library like NMSSH or BlueSocket
        // For MVP, we'll focus on WebDAV and S3
        throw UploadError.uploadFailed("SFTP not implemented in MVP")
    }

    // MARK: - Local Save

    private func saveLocally(_ chunk: EncryptedChunk, to destination: UploadDestination) async throws {
        let filename = "\(chunk.header.incidentID)/chunk_\(String(format: "%05d", chunk.header.chunkNumber)).iwc"
        let fileURL = destination.url.appendingPathComponent(filename)

        // Create directory if needed
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // Write file
        try chunk.serialize().write(to: fileURL)
    }

}
