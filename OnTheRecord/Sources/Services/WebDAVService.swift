import Foundation
import Combine

/// Service related errors
enum WebDAVError: LocalizedError {
    case invalidURL
    case authenticationFailed
    case networkError(Error)
    case uploadFailed(statusCode: Int)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid WebDAV URL"
        case .authenticationFailed: return "Authentication failed. Check credentials."
        case .networkError(let error): return "Network error: \(error.localizedDescription)"
        case .uploadFailed(let code): return "Upload failed with status code: \(code)"
        }
    }
}

/// Service to handle WebDAV uploads (Hetzner Storage Box)
@MainActor
final class WebDAVService: ObservableObject {
    static let shared = WebDAVService()
    
    private let session: URLSession
    
    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60 // 1 minute timeout for chunks
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config)
    }
    
    /// Uploads data to a WebDAV destination
    /// - Parameters:
    ///   - data: The file data to upload
    ///   - remotePath: The full destination URL (e.g. https://u1234.your-storagebox.de/incident_1/chunk_1.iwc)
    ///   - credentials: Basic auth credentials
    func upload(data: Data, to url: URL, credentials: URLCredential) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.httpBody = data
        
        // Add Basic Auth Header manually to ensure it's sent immediately
        // (URLSession sometimes waits for a 401 challenge, which slows things down)
        let authString = "\(credentials.user ?? ""):\(credentials.password ?? "")"
        if let authData = authString.data(using: .utf8) {
            let base64Auth = authData.base64EncodedString()
            request.setValue("Basic \(base64Auth)", forHTTPHeaderField: "Authorization")
        }
        
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue("\(data.count)", forHTTPHeaderField: "Content-Length")
        
        do {
            let (_, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw WebDAVError.networkError(URLError(.badServerResponse))
            }
            
            // 200 OK, 201 Created, 204 No Content are all successes for WebDAV
            guard (200...204).contains(httpResponse.statusCode) else {
                if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                    throw WebDAVError.authenticationFailed
                }
                throw WebDAVError.uploadFailed(statusCode: httpResponse.statusCode)
            }
            
            debugLog("[WebDAVService] Upload successful: \(url.lastPathComponent)")

        } catch {
            debugLog("[WebDAVService] Upload failed: \(error)")
            throw WebDAVError.networkError(error)
        }
    }
    
    // MARK: - Directory Creation (MKCOL)

    /// Directories we've already created in this session (avoids redundant MKCOL requests)
    private var createdDirectories: Set<String> = []
    private let createdDirsLock = NSLock()

    /// Ensures all parent directories exist for a given upload path on a WebDAV server.
    /// Sends MKCOL for each path component (e.g. "OnTheRecord/" then "OnTheRecord/IW-123/").
    /// HTTP 405 (Method Not Allowed) or 301 responses are treated as "directory already exists".
    func ensureDirectoriesExist(
        baseURL: URL,
        remotePath: String,
        username: String,
        password: String
    ) async {
        // Split "OnTheRecord/IW-20260130T1200-AB12/chunk_00001.iwc" into directory components
        let components = remotePath.split(separator: "/").dropLast() // Drop the filename
        var currentPath = ""

        for component in components {
            currentPath += "\(component)/"

            // Skip if already created this session
            createdDirsLock.lock()
            let alreadyCreated = createdDirectories.contains(currentPath)
            createdDirsLock.unlock()
            if alreadyCreated { continue }

            let dirURL = baseURL.appendingPathComponent(currentPath)
            var request = URLRequest(url: dirURL)
            request.httpMethod = "MKCOL"

            let authString = "\(username):\(password)"
            if let authData = authString.data(using: .utf8) {
                let base64Auth = authData.base64EncodedString()
                request.setValue("Basic \(base64Auth)", forHTTPHeaderField: "Authorization")
            }

            do {
                let (_, response) = try await session.data(for: request)
                if let httpResponse = response as? HTTPURLResponse {
                    // 201 = Created, 405 = Already exists (Method Not Allowed on existing collection),
                    // 301 = Redirect (some servers redirect to existing dir)
                    if [201, 405, 301].contains(httpResponse.statusCode) ||
                       (200...299).contains(httpResponse.statusCode) {
                        createdDirsLock.withLock {
                            createdDirectories.insert(currentPath)
                        }
                        debugLog("[WebDAVService] Directory ensured: \(currentPath) (HTTP \(httpResponse.statusCode))")
                    } else {
                        debugLog("[WebDAVService] MKCOL unexpected status \(httpResponse.statusCode) for \(currentPath)")
                    }
                }
            } catch {
                debugLog("[WebDAVService] MKCOL failed for \(currentPath): \(error.localizedDescription)")
            }
        }
    }

    /// Validates connection by attempting to list root directory (PROPFIND)
    func validateConnection(url: URL, credentials: URLCredential) async throws -> Bool {
        var request = URLRequest(url: url)
        request.httpMethod = "PROPFIND"
        request.setValue("1", forHTTPHeaderField: "Depth")
        
        let authString = "\(credentials.user ?? ""):\(credentials.password ?? "")"
        if let authData = authString.data(using: .utf8) {
            let base64Auth = authData.base64EncodedString()
            request.setValue("Basic \(base64Auth)", forHTTPHeaderField: "Authorization")
        }
        
        do {
            let (_, response) = try await session.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, 
               (200...207).contains(httpResponse.statusCode) {
                return true
            }
            return false
        } catch {
            return false
        }
    }
}
