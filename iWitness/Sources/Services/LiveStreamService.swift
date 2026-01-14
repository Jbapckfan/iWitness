import Foundation
import AVFoundation
import CryptoKit

/// Manages live streaming of video to cloud storage with shareable links
@MainActor
class LiveStreamService: ObservableObject {
    // MARK: - Published State

    @Published var isStreaming: Bool = false
    @Published var streamURL: URL?
    @Published var viewerCount: Int = 0
    @Published var segmentsUploaded: Int = 0
    @Published var streamHealth: StreamHealth = .good
    @Published var lastError: StreamError?

    enum StreamHealth {
        case good
        case degraded
        case poor
        case disconnected

        var description: String {
            switch self {
            case .good: return "Streaming"
            case .degraded: return "Buffering"
            case .poor: return "Poor Connection"
            case .disconnected: return "Disconnected"
            }
        }

        var color: String {
            switch self {
            case .good: return "green"
            case .degraded: return "yellow"
            case .poor: return "orange"
            case .disconnected: return "red"
            }
        }
    }

    // MARK: - Configuration

    struct StreamConfig {
        let destination: StreamDestination
        let quality: StreamQuality
        let segmentDuration: TimeInterval
        let enableEncryption: Bool

        static var `default`: StreamConfig {
            StreamConfig(
                destination: .cloudflareR2,
                quality: .adaptive,
                segmentDuration: 2.0,
                enableEncryption: false // For live viewing, encryption complicates playback
            )
        }
    }

    enum StreamDestination {
        case cloudflareR2
        case customServer(URL)
        case nas

        var name: String {
            switch self {
            case .cloudflareR2: return "Cloudflare"
            case .customServer: return "Custom Server"
            case .nas: return "Home Server"
            }
        }
    }

    enum StreamQuality {
        case low      // 480p, 1 Mbps
        case medium   // 720p, 2.5 Mbps
        case high     // 1080p, 5 Mbps
        case adaptive // Multi-bitrate
    }

    // MARK: - Errors

    enum StreamError: LocalizedError {
        case notConfigured
        case uploadFailed(String)
        case networkUnavailable
        case authenticationFailed

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "Streaming not configured"
            case .uploadFailed(let reason):
                return "Stream upload failed: \(reason)"
            case .networkUnavailable:
                return "Network unavailable"
            case .authenticationFailed:
                return "Authentication failed"
            }
        }
    }

    // MARK: - Private State

    private var config: StreamConfig?
    private var incidentID: String?
    private var streamID: String?
    private var uploadQueue: [StreamSegment] = []
    private var playlistContent: String = ""
    private var segmentNumber: Int = 0
    private var uploadTask: Task<Void, Never>?
    private var playlistUpdateTask: Task<Void, Never>?

    // Credentials
    private var r2AccountID: String?
    private var r2BucketName: String?
    private var r2AccessKey: String?
    private var r2SecretKey: String?
    private var customServerURL: URL?
    private var customServerAuth: (username: String, password: String)?

    // MARK: - Segment

    private struct StreamSegment {
        let number: Int
        let data: Data
        let duration: TimeInterval
        let timestamp: Date
    }

    // MARK: - Configuration

    func configureCloudflareR2(
        accountID: String,
        bucketName: String,
        accessKey: String,
        secretKey: String
    ) {
        r2AccountID = accountID
        r2BucketName = bucketName
        r2AccessKey = accessKey
        r2SecretKey = secretKey
    }

    func configureCustomServer(url: URL, username: String?, password: String?) {
        customServerURL = url
        if let username = username, let password = password {
            customServerAuth = (username, password)
        }
    }

    var isConfigured: Bool {
        r2AccountID != nil || customServerURL != nil || hasNASConfig
    }

    private var hasNASConfig: Bool {
        UserDefaults.standard.string(forKey: "nas_url") != nil
    }

    // MARK: - Stream Control

    func startStream(incidentID: String, config: StreamConfig = .default) async throws -> URL {
        guard isConfigured else {
            throw StreamError.notConfigured
        }

        self.incidentID = incidentID
        self.config = config
        self.streamID = generateStreamID()
        self.segmentNumber = 0
        self.segmentsUploaded = 0

        // Initialize HLS playlist
        initializePlaylist()

        // Upload initial playlist
        try await uploadPlaylist()

        // Generate stream URL
        let url = generateStreamURL()
        self.streamURL = url
        self.isStreaming = true

        // Start upload processor
        startUploadProcessor()

        // Start playlist updater
        startPlaylistUpdater()

        return url
    }

    func stopStream() async {
        isStreaming = false

        // Finalize playlist with ENDLIST
        finalizePlaylist()
        try? await uploadPlaylist()

        uploadTask?.cancel()
        playlistUpdateTask?.cancel()
        uploadQueue.removeAll()

        streamURL = nil
        incidentID = nil
        streamID = nil
    }

    /// Queue a video segment for streaming
    func queueSegment(data: Data, duration: TimeInterval) {
        guard isStreaming else { return }

        let segment = StreamSegment(
            number: segmentNumber,
            data: data,
            duration: duration,
            timestamp: Date()
        )

        segmentNumber += 1
        uploadQueue.append(segment)
    }

    // MARK: - HLS Playlist Management

    private func initializePlaylist() {
        playlistContent = """
        #EXTM3U
        #EXT-X-VERSION:3
        #EXT-X-TARGETDURATION:\(Int(config?.segmentDuration ?? 2))
        #EXT-X-MEDIA-SEQUENCE:0

        """
    }

    private func appendToPlaylist(segment: StreamSegment) {
        let segmentFilename = "segment_\(String(format: "%05d", segment.number)).ts"
        playlistContent += "#EXTINF:\(String(format: "%.3f", segment.duration)),\n"
        playlistContent += "\(segmentFilename)\n"
    }

    private func finalizePlaylist() {
        playlistContent += "#EXT-X-ENDLIST\n"
    }

    // MARK: - Upload Processing

    private func startUploadProcessor() {
        uploadTask = Task {
            while !Task.isCancelled && isStreaming {
                if let segment = uploadQueue.first {
                    uploadQueue.removeFirst()

                    do {
                        try await uploadSegment(segment)
                        appendToPlaylist(segment: segment)
                        segmentsUploaded += 1
                        streamHealth = .good
                    } catch {
                        // Retry logic
                        uploadQueue.insert(segment, at: 0)
                        streamHealth = .degraded
                        lastError = .uploadFailed(error.localizedDescription)
                        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second retry delay
                    }
                } else {
                    try? await Task.sleep(nanoseconds: 100_000_000) // 100ms poll
                }
            }
        }
    }

    private func startPlaylistUpdater() {
        playlistUpdateTask = Task {
            while !Task.isCancelled && isStreaming {
                try? await uploadPlaylist()
                try? await Task.sleep(nanoseconds: 2_000_000_000) // Update every 2 seconds
            }
        }
    }

    // MARK: - Upload Methods

    private func uploadSegment(_ segment: StreamSegment) async throws {
        let filename = "segment_\(String(format: "%05d", segment.number)).ts"

        if r2AccountID != nil {
            try await uploadToR2(data: segment.data, filename: filename)
        } else if let serverURL = customServerURL {
            try await uploadToCustomServer(data: segment.data, filename: filename, serverURL: serverURL)
        } else if hasNASConfig {
            try await uploadToNAS(data: segment.data, filename: filename)
        }
    }

    private func uploadPlaylist() async throws {
        let filename = "stream.m3u8"
        let data = playlistContent.data(using: .utf8) ?? Data()

        if r2AccountID != nil {
            try await uploadToR2(data: data, filename: filename, contentType: "application/vnd.apple.mpegurl")
        } else if let serverURL = customServerURL {
            try await uploadToCustomServer(data: data, filename: filename, serverURL: serverURL)
        } else if hasNASConfig {
            try await uploadToNAS(data: data, filename: filename)
        }
    }

    // MARK: - Cloudflare R2 Upload

    private func uploadToR2(data: Data, filename: String, contentType: String = "video/MP2T") async throws {
        guard let accountID = r2AccountID,
              let bucketName = r2BucketName,
              let accessKey = r2AccessKey,
              let secretKey = r2SecretKey,
              let streamID = streamID else {
            throw StreamError.notConfigured
        }

        let endpoint = "https://\(accountID).r2.cloudflarestorage.com"
        let path = "/\(bucketName)/streams/\(streamID)/\(filename)"

        guard let url = URL(string: endpoint + path) else {
            throw StreamError.uploadFailed("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.httpBody = data
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")

        // Sign request with AWS Signature V4 (R2 is S3-compatible)
        let signedRequest = try signAWSRequest(
            request: request,
            accessKey: accessKey,
            secretKey: secretKey,
            region: "auto",
            service: "s3"
        )

        let (_, response) = try await URLSession.shared.data(for: signedRequest)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw StreamError.uploadFailed("HTTP error")
        }
    }

    // MARK: - Custom Server Upload (WebDAV)

    private func uploadToCustomServer(data: Data, filename: String, serverURL: URL) async throws {
        guard let streamID = streamID else {
            throw StreamError.notConfigured
        }

        let uploadURL = serverURL
            .appendingPathComponent("streams")
            .appendingPathComponent(streamID)
            .appendingPathComponent(filename)

        var request = URLRequest(url: uploadURL)
        request.httpMethod = "PUT"
        request.httpBody = data

        if let auth = customServerAuth {
            let credentials = "\(auth.username):\(auth.password)"
            if let credData = credentials.data(using: .utf8) {
                request.setValue("Basic \(credData.base64EncodedString())", forHTTPHeaderField: "Authorization")
            }
        }

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw StreamError.uploadFailed("Upload failed")
        }
    }

    // MARK: - NAS Upload (WebDAV)

    private func uploadToNAS(data: Data, filename: String) async throws {
        guard let nasURLString = UserDefaults.standard.string(forKey: "nas_url"),
              let nasURL = URL(string: nasURLString),
              let streamID = streamID else {
            throw StreamError.notConfigured
        }

        let username = UserDefaults.standard.string(forKey: "nas_username") ?? ""
        let password = UserDefaults.standard.string(forKey: "nas_password") ?? ""

        // Create stream directory path
        let uploadURL = nasURL
            .appendingPathComponent("iwitness")
            .appendingPathComponent("streams")
            .appendingPathComponent(streamID)
            .appendingPathComponent(filename)

        // Ensure directory exists (MKCOL for WebDAV)
        try await ensureNASDirectory(streamID: streamID, nasURL: nasURL, username: username, password: password)

        var request = URLRequest(url: uploadURL)
        request.httpMethod = "PUT"
        request.httpBody = data

        let credentials = "\(username):\(password)"
        if let credData = credentials.data(using: .utf8) {
            request.setValue("Basic \(credData.base64EncodedString())", forHTTPHeaderField: "Authorization")
        }

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) || httpResponse.statusCode == 201 else {
            throw StreamError.uploadFailed("NAS upload failed")
        }
    }

    private func ensureNASDirectory(streamID: String, nasURL: URL, username: String, password: String) async throws {
        let directories = ["iwitness", "iwitness/streams", "iwitness/streams/\(streamID)"]

        for dir in directories {
            let dirURL = nasURL.appendingPathComponent(dir)
            var request = URLRequest(url: dirURL)
            request.httpMethod = "MKCOL"

            let credentials = "\(username):\(password)"
            if let credData = credentials.data(using: .utf8) {
                request.setValue("Basic \(credData.base64EncodedString())", forHTTPHeaderField: "Authorization")
            }

            // Ignore errors - directory might already exist
            _ = try? await URLSession.shared.data(for: request)
        }
    }

    // MARK: - URL Generation

    private func generateStreamID() -> String {
        // Short, shareable ID
        let chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789" // Avoid ambiguous chars
        return String((0..<8).map { _ in chars.randomElement()! })
    }

    private func generateStreamURL() -> URL {
        guard let streamID = streamID else {
            return URL(string: "https://iwitness.app/stream/error")!
        }

        // For R2, generate public URL
        if let accountID = r2AccountID, let bucketName = r2BucketName {
            // R2 public bucket URL or custom domain
            let publicURL = "https://\(bucketName).\(accountID).r2.dev/streams/\(streamID)/stream.m3u8"
            return URL(string: publicURL) ?? URL(string: "https://iwitness.app/stream/\(streamID)")!
        }

        // For custom server
        if let serverURL = customServerURL {
            return serverURL
                .appendingPathComponent("streams")
                .appendingPathComponent(streamID)
                .appendingPathComponent("stream.m3u8")
        }

        // For NAS - need external access URL
        // This would need to be configured by user (e.g., via DDNS)
        if let nasExternalURL = UserDefaults.standard.string(forKey: "nas_external_url"),
           let url = URL(string: nasExternalURL) {
            return url
                .appendingPathComponent("iwitness/streams")
                .appendingPathComponent(streamID)
                .appendingPathComponent("stream.m3u8")
        }

        // Fallback - generate a viewer page URL
        return URL(string: "https://iwitness.app/watch/\(streamID)")!
    }

    /// Generate a short share link for the stream
    func generateShareLink() -> String {
        guard let streamID = streamID else { return "" }
        return "https://iwitness.app/watch/\(streamID)"
    }

    /// Generate share message with stream link
    func generateShareMessage() -> String {
        let link = generateShareLink()
        return "🔴 LIVE: I'm documenting an incident. Watch live: \(link)"
    }

    // MARK: - AWS Signature V4

    private func signAWSRequest(
        request: URLRequest,
        accessKey: String,
        secretKey: String,
        region: String,
        service: String
    ) throws -> URLRequest {
        var signedRequest = request

        let date = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        let amzDate = dateFormatter.string(from: date)

        dateFormatter.dateFormat = "yyyyMMdd"
        let dateStamp = dateFormatter.string(from: date)

        signedRequest.setValue(amzDate, forHTTPHeaderField: "x-amz-date")
        signedRequest.setValue(request.url?.host ?? "", forHTTPHeaderField: "Host")

        // Simplified signing for MVP - in production use proper AWS4-HMAC-SHA256
        let payloadHash = SHA256.hash(data: request.httpBody ?? Data())
        let payloadHashHex = payloadHash.compactMap { String(format: "%02x", $0) }.joined()
        signedRequest.setValue(payloadHashHex, forHTTPHeaderField: "x-amz-content-sha256")

        // Create canonical request and sign
        let credential = "\(accessKey)/\(dateStamp)/\(region)/\(service)/aws4_request"

        // For MVP, use a simplified auth header
        // In production, implement full AWS Signature V4
        let authHeader = "AWS4-HMAC-SHA256 Credential=\(credential), SignedHeaders=host;x-amz-content-sha256;x-amz-date, Signature=\(computeSignature(secretKey: secretKey, dateStamp: dateStamp, region: region, service: service, request: signedRequest))"

        signedRequest.setValue(authHeader, forHTTPHeaderField: "Authorization")

        return signedRequest
    }

    private func computeSignature(secretKey: String, dateStamp: String, region: String, service: String, request: URLRequest) -> String {
        // Simplified signature computation
        let key = SymmetricKey(data: "AWS4\(secretKey)".data(using: .utf8)!)
        let dateKey = HMAC<SHA256>.authenticationCode(for: dateStamp.data(using: .utf8)!, using: key)
        let dateRegionKey = HMAC<SHA256>.authenticationCode(for: region.data(using: .utf8)!, using: SymmetricKey(data: Data(dateKey)))
        let dateRegionServiceKey = HMAC<SHA256>.authenticationCode(for: service.data(using: .utf8)!, using: SymmetricKey(data: Data(dateRegionKey)))
        let signingKey = HMAC<SHA256>.authenticationCode(for: "aws4_request".data(using: .utf8)!, using: SymmetricKey(data: Data(dateRegionServiceKey)))

        // Create string to sign (simplified)
        let stringToSign = "\(request.httpMethod ?? "PUT")\(request.url?.path ?? "")"
        let signature = HMAC<SHA256>.authenticationCode(for: stringToSign.data(using: .utf8)!, using: SymmetricKey(data: Data(signingKey)))

        return signature.compactMap { String(format: "%02x", $0) }.joined()
    }
}
