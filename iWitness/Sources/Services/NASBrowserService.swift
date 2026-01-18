import Foundation
import AVFoundation

/// Read-only service for browsing and playing back recordings from NAS
/// Deliberately has NO delete capability - recordings cannot be destroyed
@MainActor
class NASBrowserService: ObservableObject {
    // MARK: - Published State

    @Published var incidents: [Incident] = []
    @Published var isLoading = false
    @Published var error: BrowserError?
    @Published var currentlyPlaying: Incident?
    @Published var decryptionProgress: Double = 0

    // MARK: - Types

    struct Incident: Identifiable {
        let id: String // incidentID
        let date: Date
        var chunkCount: Int
        var totalSize: Int64
        var isDecrypted: Bool = false
        var localPlaybackURL: URL?
    }

    enum BrowserError: LocalizedError {
        case nasNotConfigured
        case connectionFailed(String)
        case decryptionFailed(String)
        case noChunksFound

        var errorDescription: String? {
            switch self {
            case .nasNotConfigured:
                return "NAS is not configured"
            case .connectionFailed(let reason):
                return "Connection failed: \(reason)"
            case .decryptionFailed(let reason):
                return "Decryption failed: \(reason)"
            case .noChunksFound:
                return "No recording chunks found"
            }
        }
    }

    // MARK: - Dependencies

    private let encryptionService = EncryptionService()

    // MARK: - NAS Configuration

    private var nasURL: URL? {
        guard let urlString = UserDefaults.standard.string(forKey: "nas_url") else { return nil }
        return URL(string: urlString)
    }

    private var nasUsername: String? {
        UserDefaults.standard.string(forKey: "nas_username")
    }

    private var nasPassword: String? {
        KeychainHelper.shared.read(service: "iWitness", account: "nas_password")
    }

    private var authHeader: String? {
        guard let username = nasUsername, let password = nasPassword else { return nil }
        let authString = "\(username):\(password)"
        guard let authData = authString.data(using: .utf8) else { return nil }
        return "Basic \(authData.base64EncodedString())"
    }

    // MARK: - Browse Recordings

    /// Fetches list of incidents from NAS (read-only)
    func loadIncidents() async {
        guard let baseURL = nasURL else {
            error = .nasNotConfigured
            return
        }

        isLoading = true
        error = nil
        incidents = []

        let iWitnessURL = baseURL.appendingPathComponent("iWitness")

        do {
            // List incident directories
            let incidentIDs = try await listWebDAVDirectory(iWitnessURL)

            var loadedIncidents: [Incident] = []

            for incidentID in incidentIDs {
                // Get chunk count for each incident
                let incidentURL = iWitnessURL.appendingPathComponent(incidentID)
                let chunks = try await listWebDAVDirectory(incidentURL)
                let chunkCount = chunks.filter { $0.hasSuffix(".iwc") }.count

                // Parse date from incident ID (format: IW-YYYYMMDDTHHMMSSZ-XXXX)
                let date = parseIncidentDate(incidentID) ?? Date()

                loadedIncidents.append(Incident(
                    id: incidentID,
                    date: date,
                    chunkCount: chunkCount,
                    totalSize: 0 // Would need additional PROPFIND for sizes
                ))
            }

            // Sort by date, newest first
            incidents = loadedIncidents.sorted { $0.date > $1.date }

        } catch {
            self.error = .connectionFailed(error.localizedDescription)
        }

        isLoading = false
    }

    // MARK: - Playback (Decrypt + Assemble)

    /// Decrypts and prepares an incident for playback
    func prepareForPlayback(_ incident: Incident) async throws -> URL {
        guard let baseURL = nasURL else {
            throw BrowserError.nasNotConfigured
        }

        decryptionProgress = 0
        currentlyPlaying = incident

        let incidentURL = baseURL.appendingPathComponent("iWitness/\(incident.id)")

        // Get list of chunks
        let chunkFiles = try await listWebDAVDirectory(incidentURL)
            .filter { $0.hasSuffix(".iwc") }
            .sorted() // Ensure order: chunk_00001.iwc, chunk_00002.iwc, etc.

        guard !chunkFiles.isEmpty else {
            throw BrowserError.noChunksFound
        }

        // Create temp directory for this incident
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("iWitness_playback")
            .appendingPathComponent(incident.id)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Download and decrypt each chunk
        var decryptedChunks: [Data] = []

        for (index, chunkFile) in chunkFiles.enumerated() {
            let chunkURL = incidentURL.appendingPathComponent(chunkFile)

            // Download chunk
            let encryptedData = try await downloadFile(chunkURL)

            // Parse encrypted chunk
            let decoder = JSONDecoder()
            let encryptedChunk = try decoder.decode(EncryptedChunk.self, from: encryptedData)

            // Decrypt
            let decryptedData = try encryptionService.decryptChunk(encryptedChunk)
            decryptedChunks.append(decryptedData)

            // Update progress
            decryptionProgress = Double(index + 1) / Double(chunkFiles.count)
        }

        // Combine chunks into a playable video file
        let outputURL = tempDir.appendingPathComponent("playback.mov")
        try await assembleVideoChunks(decryptedChunks, to: outputURL)

        return outputURL
    }

    // MARK: - WebDAV Operations

    private func listWebDAVDirectory(_ url: URL) async throws -> [String] {
        var request = URLRequest(url: url)
        request.httpMethod = "PROPFIND"
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.setValue("application/xml", forHTTPHeaderField: "Content-Type")

        if let auth = authHeader {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
        }

        // PROPFIND body to get directory listing
        let propfindBody = """
        <?xml version="1.0" encoding="utf-8"?>
        <D:propfind xmlns:D="DAV:">
            <D:prop>
                <D:displayname/>
                <D:resourcetype/>
            </D:prop>
        </D:propfind>
        """
        request.httpBody = propfindBody.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) || httpResponse.statusCode == 207 else {
            throw BrowserError.connectionFailed("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }

        // Parse XML response to extract directory names
        return parseWebDAVResponse(data, baseURL: url)
    }

    private func downloadFile(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        if let auth = authHeader {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw BrowserError.connectionFailed("Download failed")
        }

        return data
    }

    // MARK: - Helpers

    private func parseWebDAVResponse(_ data: Data, baseURL: URL) -> [String] {
        // Simple XML parsing for directory listing
        guard let xmlString = String(data: data, encoding: .utf8) else { return [] }

        var entries: [String] = []

        // Extract hrefs from response (simplified parsing)
        let pattern = "<D:href>([^<]+)</D:href>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }

        let matches = regex.matches(in: xmlString, options: [], range: NSRange(xmlString.startIndex..., in: xmlString))

        for match in matches {
            if let range = Range(match.range(at: 1), in: xmlString) {
                var path = String(xmlString[range])

                // URL decode
                path = path.removingPercentEncoding ?? path

                // Extract just the filename/directory name
                if let lastComponent = path.split(separator: "/").last {
                    let name = String(lastComponent)
                    // Skip the base directory itself
                    if !name.isEmpty && name != baseURL.lastPathComponent {
                        entries.append(name)
                    }
                }
            }
        }

        return entries
    }

    private func parseIncidentDate(_ incidentID: String) -> Date? {
        // Format: IW-20240115T143052Z-A1B2
        let components = incidentID.split(separator: "-")
        guard components.count >= 2 else { return nil }

        let dateString = String(components[1])

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withYear, .withMonth, .withDay, .withTime, .withTimeZone]

        // Try parsing with T separator
        if let date = formatter.date(from: dateString) {
            return date
        }

        // Try manual parsing (YYYYMMDDTHHMMSSZ format without separators)
        let cleanDate = dateString.replacingOccurrences(of: "T", with: "")
            .replacingOccurrences(of: "Z", with: "")

        let manualFormatter = DateFormatter()
        manualFormatter.dateFormat = "yyyyMMddHHmmss"
        manualFormatter.timeZone = TimeZone(identifier: "UTC")

        return manualFormatter.date(from: cleanDate)
    }

    private func assembleVideoChunks(_ chunks: [Data], to outputURL: URL) async throws {
        // For MVP: Write raw video data
        // In production: Would use AVAssetWriter to properly mux video/audio

        // Remove existing file
        try? FileManager.default.removeItem(at: outputURL)

        // Combine all chunk data
        var combinedData = Data()
        for chunk in chunks {
            combinedData.append(chunk)
        }

        // Write to file
        try combinedData.write(to: outputURL)
    }

    // MARK: - Cleanup

    func clearPlaybackCache() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("iWitness_playback")
        try? FileManager.default.removeItem(at: tempDir)
        currentlyPlaying = nil
        decryptionProgress = 0
    }
}
