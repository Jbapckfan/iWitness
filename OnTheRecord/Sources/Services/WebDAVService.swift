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
