import Foundation
import Network
import CryptoKit

/// Manages upload queue and multi-destination chunk transmission
/// Uses background URLSession to ensure uploads continue even if app is suspended
class UploadService: NSObject, ObservableObject, URLSessionTaskDelegate, URLSessionDataDelegate {
    // MARK: - Published State

    @MainActor @Published var queueDepth: Int = 0
    @MainActor @Published var chunksUploaded: Int = 0
    @MainActor @Published var uploadSpeed: Double = 0 // bytes per second
    @MainActor @Published var isUploading: Bool = false
    @MainActor @Published var currentDestination: String = ""
    @MainActor @Published var lastError: UploadError?

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
    private var backgroundSession: URLSession!
    
    // Track active tasks to map back to metadata
    private var activeTasks: [Int: QueuedChunk] = [:]
    private let activeTasksLock = NSLock()
    
    // Queue that persists across launches (simplified for MVP - in prod use CoreData/Realm)
    private var pendingQueue: [QueuedChunk] = []
    private let queueLock = NSLock()
    
    private let networkMonitor = NWPathMonitor()
    private var isNetworkAvailable = true
    
    // Upload statistics
    private var totalBytesUploaded: Int64 = 0
    private var sessionStartTime: Date?

    // MARK: - Queue Item
    
    struct QueuedChunk: Codable {
        let chunkID: String
        let relativePath: String // Relative to Application Support
        let incidentID: String
        let chunkNumber: Int
        let addedAt: Date
        let fileHash: String // SHA256 of the data for integrity/S3
        var uploadAttempts: Int = 0
        var uploadedTo: Set<String> = []
        
        var fileURL: URL? {
            guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
            return support.appendingPathComponent(relativePath)
        }
    }
    
    // MARK: - Errors
    
    enum UploadError: LocalizedError {
        case noDestinations
        case networkUnavailable
        case authenticationFailed
        case uploadFailed(String)
        case allDestinationsFailed
        case fileNotFound
        
        var errorDescription: String? {
            switch self {
            case .noDestinations: return "No upload destinations configured"
            case .networkUnavailable: return "Network is unavailable"
            case .authenticationFailed: return "Authentication failed"
            case .uploadFailed(let reason): return "Upload failed: \(reason)"
            case .allDestinationsFailed: return "All upload destinations failed"
            case .fileNotFound: return "Source file verification failed"
            }
        }
    }

    // MARK: - Initialization

    override init() {
        super.init()
        setupBackgroundSession()
        setupNetworkMonitor()
        loadPersistedQueue()
    }

    private func setupBackgroundSession() {
        let config = URLSessionConfiguration.background(withIdentifier: "com.iwitness.backgroundUpload")
        config.isDiscretionary = false // We want it to happen ASAP
        config.sessionSendsLaunchEvents = true
        config.shouldUseExtendedBackgroundIdleMode = true
        config.waitsForConnectivity = true
        
        // Create session with self as delegate
        self.backgroundSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    private func setupNetworkMonitor() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                self?.isNetworkAvailable = path.status == .satisfied
                if path.status == .satisfied {
                    self?.processQueue()
                }
            }
        }
        networkMonitor.start(queue: DispatchQueue.global(qos: .utility))
    }
    
    // MARK: - Queue Persistence (Production Hardening)
    
    private let queuePersistenceKey = "com.iwitness.uploadQueue"
    
    private func loadPersistedQueue() {
        guard let data = UserDefaults.standard.data(forKey: queuePersistenceKey),
              let queue = try? JSONDecoder().decode([QueuedChunk].self, from: data) else {
            return
        }
        
        queueLock.lock()
        pendingQueue = queue
        queueLock.unlock()
        
        Task { @MainActor in
            self.queueDepth = queue.count
        }
        
        if !queue.isEmpty {
            print("[OnTheRecord] Restored \(queue.count) pending uploads from previous session")
            processQueue()
        }
    }
    
    private func persistQueue() {
        queueLock.lock()
        let queue = pendingQueue
        queueLock.unlock()
        
        if let data = try? JSONEncoder().encode(queue) {
            UserDefaults.standard.set(data, forKey: queuePersistenceKey)
        }
    }

    // MARK: - Configuration

    func configureDestinations(_ destinations: [UploadDestination]) {
        self.destinations = destinations.sorted { $0.priority < $1.priority }
    }

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
    
    /// Queue a file handling the OnTheRecord container format (IWC)
    /// - Parameters:
    ///   - url: URL to the ready-to-upload .iwc file (EncryptedChunk serialized)
    ///   - incidentID: Incident ID
    ///   - chunkNumber: Sequence number
    ///   - hash: SHA256 hash of the file content
    func queueChunk(fileURL: URL, incidentID: String, chunkNumber: Int, hash: String) {
        // Calculate relative path for persistence
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
              let relativePath = fileURL.path.components(separatedBy: support.path).last?.trimmingCharacters(in: CharacterSet(charactersIn: "/")) else {
            print("[UploadService] Failed to determine relative path for \(fileURL)")
            return
        }
        
        let queuedChunk = QueuedChunk(
            chunkID: UUID().uuidString,
            relativePath: relativePath,
            incidentID: incidentID,
            chunkNumber: chunkNumber,
            addedAt: Date(),
            fileHash: hash
        )
        
        queueLock.lock()
        pendingQueue.append(queuedChunk)
        queueLock.unlock()
        
        persistQueue()
        
        Task { @MainActor in
            self.queueDepth = pendingQueue.count
        }
        
        processQueue()
    }
    
    private func processQueue() {
        guard isNetworkAvailable else { return }
        
        // Safety: Warn user if queue is accumulating too much (Edge Case: Stranded Data)
        queueLock.lock()
        let count = pendingQueue.count
        queueLock.unlock()
        
        if count > 50 && count % 50 == 0 { // Notify at 50, 100, etc.
            Task { @MainActor in
                AlertService().triggerLocalNotification(
                    title: "Upload Queue High",
                    body: "\(count) items pending upload. Check your internet connection or storage destination.",
                    identifier: "upload_queue_warning"
                )
            }
        }
        
        queueLock.lock()
        for i in 0..<pendingQueue.count {
            let chunk = pendingQueue[i]
            
            // Check if fully uploaded
            if hasUploadedToAllDestinations(chunk) {
                continue
            }
            
            // Verify file exists
            guard let url = chunk.fileURL, FileManager.default.fileExists(atPath: url.path) else {
                print("[UploadService] Error: File missing for chunk \(chunk.chunkNumber)")
                continue
            }
            
            // Initiate uploads for missing destinations
            for destination in destinations {
                if !chunk.uploadedTo.contains(destination.name) {
                    startBackgroundUpload(chunk: chunk, destination: destination)
                }
            }
        }
        queueLock.unlock()
    }
    
    private func hasUploadedToAllDestinations(_ chunk: QueuedChunk) -> Bool {
        // We consider it "done" if uploaded to at least one primary destination if multiple exist
        // Or all configured.
        // For highest assurance: Must upload to ALL.
        guard !destinations.isEmpty else { return true }
        return destinations.allSatisfy { chunk.uploadedTo.contains($0.name) }
    }
    
    // MARK: - Background Upload Initiation
    
    private func startBackgroundUpload(chunk: QueuedChunk, destination: UploadDestination) {
        // Use the persistent file directly - NO COPYING to temp
        guard let sourceURL = chunk.fileURL else { return }
        
        do {
            var request: URLRequest?
            
            switch destination.type {
            case .webdav:
                request = try createWebDAVRequest(chunk: chunk, destination: destination)
            case .s3Compatible:
                request = try createS3Request(chunk: chunk, destination: destination)
            default:
                Task { try await saveLocally(chunk: chunk, destination: destination) }
                return
            }
            
            if let request = request {
                // uploadTask(withRequest:fromFile:) enables true background upload
                let task = backgroundSession.uploadTask(with: request, fromFile: sourceURL)
                task.taskDescription = "\(chunk.chunkID)|\(destination.name)"
                
                activeTasksLock.lock()
                activeTasks[task.taskIdentifier] = chunk
                activeTasksLock.unlock()
                
                task.resume()
                
                Task { @MainActor in
                    self.isUploading = true
                }
            }
            
        } catch {
            print("[OnTheRecord] Failed to start background upload: \(error)")
        }
    }
    
    // MARK: - Request Creation
    
    private func createWebDAVRequest(chunk: QueuedChunk, destination: UploadDestination) throws -> URLRequest {
        let filename = "OnTheRecord/\(chunk.incidentID)/chunk_\(String(format: "%05d", chunk.chunkNumber)).iwc"
        let uploadURL = destination.url.appendingPathComponent(filename)

        var request = URLRequest(url: uploadURL)
        request.httpMethod = "PUT"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

        if let creds = destination.credentials,
           let username = creds.username,
           let password = creds.password {
            let authString = "\(username):\(password)"
            if let authData = authString.data(using: .utf8) {
                let base64Auth = authData.base64EncodedString()
                request.setValue("Basic \(base64Auth)", forHTTPHeaderField: "Authorization")
            }
        }
        
        // Note: MKCOL logic for creating directories is tricky in background sessions
        // because we can't chain dependent requests easily.
        // In this architecture, we assume the directory structure is pre-created or flat,
        // OR we rely on the server handling it.
        // Standard WebDAV requires parent dirs to exist.
        // For MVP High Assurance, we assume the root (OnTheRecord) exists.
        
        return request
    }
    
    private func createS3Request(chunk: QueuedChunk, destination: UploadDestination) throws -> URLRequest {
        guard let creds = destination.credentials,
              let accessKey = creds.apiKey,
              let _ = creds.secretKey else {
            throw UploadError.authenticationFailed
        }

        let key = "\(chunk.incidentID)/chunk_\(String(format: "%05d", chunk.chunkNumber)).iwc"
        
        var request = URLRequest(url: destination.url.appendingPathComponent(key))
        request.httpMethod = "PUT"
        
        let contentHash = chunk.fileHash
        
        let date = ISO8601DateFormatter().string(from: Date())
        request.setValue(date, forHTTPHeaderField: "x-amz-date")
        request.setValue(contentHash, forHTTPHeaderField: "x-amz-content-sha256")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        
        // Sign
        let signature = "placeholder_sig" 
        request.setValue("AWS4-HMAC-SHA256 Credential=\(accessKey)/...,Signature=\(signature)", forHTTPHeaderField: "Authorization")
        
        return request
    }
    
    // MARK: - Local Save
    
    private func saveLocally(chunk: QueuedChunk, destination: UploadDestination) async throws {
        guard let sourceURL = chunk.fileURL else { return }
        let filename = "chunk_\(String(format: "%05d", chunk.chunkNumber)).iwc"
        let destURL = destination.url.appendingPathComponent(filename)
        
        try? FileManager.default.removeItem(at: destURL)
        try FileManager.default.copyItem(at: sourceURL, to: destURL)
        
        handleSuccess(chunkID: chunk.chunkID, destinationName: destination.name)
    }

    // MARK: - URLSessionDelegate Methods
    
    private let maxRetryAttempts = 5
    private let retryDelays: [TimeInterval] = [1, 5, 30, 120, 600] // 1s, 5s, 30s, 2min, 10min
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let description = task.taskDescription else { return }
        let components = description.split(separator: "|")
        guard components.count == 2 else { return }
        
        let chunkID = String(components[0])
        let destName = String(components[1])
        
        activeTasksLock.lock()
        activeTasks.removeValue(forKey: task.taskIdentifier)
        activeTasksLock.unlock()
        
        if let error = error {
            print("[OnTheRecord] Background upload failed for \(chunkID) to \(destName): \(error)")
            handleFailure(chunkID: chunkID, destinationName: destName)
        } else {
            // Check status code
            if let response = task.response as? HTTPURLResponse, (200...299).contains(response.statusCode) {
                handleSuccess(chunkID: chunkID, destinationName: destName)
            } else {
                let statusCode = (task.response as? HTTPURLResponse)?.statusCode ?? 0
                print("[OnTheRecord] Server error for \(chunkID) to \(destName): \(statusCode)")
                handleFailure(chunkID: chunkID, destinationName: destName)
            }
        }
    }
    
    private func handleFailure(chunkID: String, destinationName: String) {
        queueLock.lock()
        if let index = pendingQueue.firstIndex(where: { $0.chunkID == chunkID }) {
            var chunk = pendingQueue[index]
            chunk.uploadAttempts += 1
            pendingQueue[index] = chunk
            
            if chunk.uploadAttempts < maxRetryAttempts {
                // Schedule retry with exponential backoff
                let delayIndex = min(chunk.uploadAttempts - 1, retryDelays.count - 1)
                let delay = retryDelays[delayIndex]
                print("[OnTheRecord] Retry \(chunk.uploadAttempts) for \(chunkID) in \(delay)s")
                
                // Find the destination and retry after delay
                if let destination = destinations.first(where: { $0.name == destinationName }) {
                    let chunkCopy = chunk
                    DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
                        self?.startBackgroundUpload(chunk: chunkCopy, destination: destination)
                    }
                }
            } else {
                print("[OnTheRecord] Max retries reached for \(chunkID). Will retry when network allows.")
            }
        }
        queueLock.unlock()
        
        persistQueue()
    }
    
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        // Call system completion handler if stored
        DispatchQueue.main.async {
            // (In AppDelegate we would store the completion handler)
        }
    }
    
    private func handleSuccess(chunkID: String, destinationName: String) {
        queueLock.lock()
        if let index = pendingQueue.firstIndex(where: { $0.chunkID == chunkID }) {
            var chunk = pendingQueue[index]
            chunk.uploadedTo.insert(destinationName)
            pendingQueue[index] = chunk
            
            // Check if fully complete
            if hasUploadedToAllDestinations(chunk) {
                pendingQueue.remove(at: index)
                Task { @MainActor in
                    self.chunksUploaded += 1
                }
            }
        }
        queueLock.unlock()
        
        persistQueue() // Production hardening: persist completed state
        
        Task { @MainActor in
            self.queueDepth = pendingQueue.count
            if self.pendingQueue.isEmpty {
                self.isUploading = false
            }
        }
    }
}

