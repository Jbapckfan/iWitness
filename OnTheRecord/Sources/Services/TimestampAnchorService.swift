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

        return anchor
    }

    /// Reset chain for new incident
    func startNewChain(incidentID: String) {
        lastAnchorHash = nil
        anchors = []
        debugLog("[TimestampAnchor] New chain started for \(incidentID)")
    }

    /// Export anchor chain for an incident (included in evidence package)
    func exportAnchors(incidentID: String) throws -> Data {
        let incidentAnchors = anchors.filter { $0.incidentID == incidentID }
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
