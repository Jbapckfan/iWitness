import Foundation
import CryptoKit

/// Anchors evidence timestamps to make them harder to forge
/// Uses hash chains and system uptime (immune to clock manipulation) alongside wall clock
@MainActor
class TimestampAnchorService: ObservableObject {
    static let shared = TimestampAnchorService()

    // MARK: - Types

    struct TimestampAnchor: Codable {
        let wallClockTime: Date
        let systemUptime: TimeInterval       // ProcessInfo.processInfo.systemUptime (immune to clock changes)
        let kernelBootTime: Date             // Computed from uptime, harder to fake
        let chunkHash: String                // SHA-256 of the chunk
        let previousAnchorHash: String?      // Hash chain
        let anchorHash: String               // Hash of this anchor (for chain)
        let incidentID: String
        let chunkNumber: Int
    }

    // MARK: - State

    private var lastAnchorHash: String?
    private var anchors: [TimestampAnchor] = []
    private var currentIncidentID: String?

    // MARK: - Disk Persistence

    /// Directory for a given incident's pending uploads (matches ChunkWriter / EvidenceExportService layout)
    private func anchorsDirectory(for incidentID: String) -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("OnTheRecord", isDirectory: true)
            .appendingPathComponent("PendingUploads", isDirectory: true)
            .appendingPathComponent(incidentID, isDirectory: true)
    }

    /// Append a single anchor as one line of JSON to the JSONL file (crash-safe incremental writes)
    private func persistAnchor(_ anchor: TimestampAnchor, incidentID: String) {
        guard let data = try? JSONEncoder().encode(anchor),
              let line = String(data: data, encoding: .utf8) else {
            debugLog("[TimestampAnchor] Failed to encode anchor for disk persistence")
            return
        }

        let dir = anchorsDirectory(for: incidentID)
        let filePath = dir.appendingPathComponent("timestamp_anchors.jsonl")

        // Ensure directory exists
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            debugLog("[TimestampAnchor] Failed to create anchors directory: \(error.localizedDescription)")
            return
        }

        let lineData = (line + "\n").data(using: .utf8)!

        // Append to existing file, or create if first write
        if let handle = try? FileHandle(forWritingTo: filePath) {
            handle.seekToEndOfFile()
            handle.write(lineData)
            handle.closeFile()
        } else {
            do {
                try lineData.write(to: filePath)
            } catch {
                debugLog("[TimestampAnchor] Failed to create anchors file: \(error.localizedDescription)")
            }
        }
    }

    /// Load anchors from the JSONL file on disk (crash recovery)
    func loadAnchors(incidentID: String) -> [TimestampAnchor] {
        if !anchors.isEmpty {
            return anchors.filter { $0.incidentID == incidentID }
        }
        // Fall back to disk
        let filePath = anchorsDirectory(for: incidentID).appendingPathComponent("timestamp_anchors.jsonl")
        guard let content = try? String(contentsOf: filePath, encoding: .utf8) else {
            debugLog("[TimestampAnchor] No anchors file found on disk for \(incidentID)")
            return []
        }
        let decoded = content.split(separator: "\n").compactMap { line in
            try? JSONDecoder().decode(TimestampAnchor.self, from: Data(line.utf8))
        }
        debugLog("[TimestampAnchor] Recovered \(decoded.count) anchors from disk for \(incidentID)")
        return decoded
    }

    // MARK: - Public API

    /// Create a timestamp anchor for an encrypted chunk
    func anchorTimestamp(chunkHash: Data, incidentID: String, chunkNumber: Int) -> TimestampAnchor {
        let uptime = ProcessInfo.processInfo.systemUptime
        let bootTime = Date().addingTimeInterval(-uptime)
        let chunkHashString = chunkHash.map { String(format: "%02x", $0) }.joined()

        // Build the anchor
        let anchorData = "\(Date().timeIntervalSince1970)|\(uptime)|\(bootTime.timeIntervalSince1970)|\(chunkHashString)|\(lastAnchorHash ?? "genesis")"
        let anchorHash = SHA256.hash(data: Data(anchorData.utf8)).map { String(format: "%02x", $0) }.joined()

        let anchor = TimestampAnchor(
            wallClockTime: Date(),
            systemUptime: uptime,
            kernelBootTime: bootTime,
            chunkHash: chunkHashString,
            previousAnchorHash: lastAnchorHash,
            anchorHash: anchorHash,
            incidentID: incidentID,
            chunkNumber: chunkNumber
        )

        lastAnchorHash = anchorHash
        anchors.append(anchor)
        persistAnchor(anchor, incidentID: incidentID)

        return anchor
    }

    /// Reset chain for new incident
    func startNewChain(incidentID: String) {
        lastAnchorHash = nil
        anchors = []
        currentIncidentID = incidentID

        // Remove any stale anchors file so the new chain starts fresh
        let filePath = anchorsDirectory(for: incidentID).appendingPathComponent("timestamp_anchors.jsonl")
        try? FileManager.default.removeItem(at: filePath)

        debugLog("[TimestampAnchor] New chain started for \(incidentID)")
    }

    /// Export anchor chain for an incident (included in evidence package)
    /// Falls back to disk if in-memory anchors are empty (crash recovery case)
    func exportAnchors(incidentID: String) throws -> Data {
        let incidentAnchors = loadAnchors(incidentID: incidentID)
        return try JSONEncoder().encode(incidentAnchors)
    }

    /// Verify a chain of anchors (checks hash continuity)
    static func verifyChain(_ anchors: [TimestampAnchor]) -> Bool {
        for (index, anchor) in anchors.enumerated() {
            if index == 0 {
                if anchor.previousAnchorHash != nil {
                    debugLog("[TimestampAnchor] Verification failed: genesis anchor has previous hash")
                    return false
                }
            } else {
                if anchor.previousAnchorHash != anchors[index - 1].anchorHash {
                    debugLog("[TimestampAnchor] Verification failed at chunk \(anchor.chunkNumber): chain broken")
                    return false
                }
            }

            // Verify uptime consistency (should always increase)
            if index > 0 && anchor.systemUptime <= anchors[index - 1].systemUptime {
                debugLog("[TimestampAnchor] Verification failed: system uptime decreased (clock manipulation suspected)")
                return false
            }
        }
        return true
    }
}
