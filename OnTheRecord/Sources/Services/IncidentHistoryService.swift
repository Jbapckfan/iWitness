import Foundation

/// Tracks incident lifecycle for retention management.
/// Safety invariant: the most recent incident is NEVER eligible for deletion.
@MainActor
class IncidentHistoryService: ObservableObject {
    static let shared = IncidentHistoryService()

    struct IncidentRecord: Codable, Identifiable {
        let id: String           // incident ID (IW-...)
        let startTime: Date
        var endTime: Date?
        var estimatedSizeBytes: Int64
        var retentionStatus: RetentionStatus
        var fullyUploaded: Bool

        enum RetentionStatus: String, Codable {
            case active         // currently recording
            case kept           // user explicitly chose to keep
            case pendingReview  // eligible for cleanup prompt
            case deleted        // cleaned up
        }

        var formattedSize: String {
            ByteCountFormatter.string(fromByteCount: estimatedSizeBytes, countStyle: .file)
        }

        var formattedDuration: String {
            guard let end = endTime else { return "Recording..." }
            let duration = end.timeIntervalSince(startTime)
            let m = Int(duration) / 60, s = Int(duration) % 60
            return String(format: "%d:%02d", m, s)
        }
    }

    @Published var incidents: [IncidentRecord] = []

    private let storageKey = "incident_history"

    private init() { load() }

    // MARK: - Lifecycle

    func registerIncident(id: String) {
        let record = IncidentRecord(
            id: id, startTime: Date(), endTime: nil,
            estimatedSizeBytes: 0, retentionStatus: .active, fullyUploaded: false
        )
        incidents.append(record)
        save()
    }

    func markIncidentStopped(id: String, estimatedBytes: Int64) {
        guard let idx = incidents.firstIndex(where: { $0.id == id }) else { return }
        incidents[idx].endTime = Date()
        incidents[idx].estimatedSizeBytes = estimatedBytes
        incidents[idx].retentionStatus = .kept // default to kept until review
        save()
    }

    func promoteEligibleIncidents() {
        // Only incidents where user has SINCE started a new recording can be reviewed.
        // The most recent incident is NEVER eligible.
        guard incidents.count >= 2 else { return }
        for i in 0..<(incidents.count - 1) {
            if incidents[i].retentionStatus == .kept {
                incidents[i].retentionStatus = .pendingReview
            }
        }
        save()
    }

    var incidentsPendingReview: [IncidentRecord] {
        incidents.filter { $0.retentionStatus == .pendingReview }
    }

    func keepIncident(id: String) {
        guard let idx = incidents.firstIndex(where: { $0.id == id }) else { return }
        incidents[idx].retentionStatus = .kept
        save()
    }

    func deleteIncidentData(id: String) {
        // SAFETY: Never delete the most recent incident
        guard let mostRecent = incidents.last, mostRecent.id != id else {
            debugLog("[IncidentHistory] REFUSED to delete most recent incident \(id)")
            return
        }
        guard let idx = incidents.firstIndex(where: { $0.id == id }) else { return }

        // Delete local chunk files
        let fm = FileManager.default
        if let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let chunkDir = support.appendingPathComponent("OnTheRecord/PendingUploads/\(id)")
            try? fm.removeItem(at: chunkDir)
        }

        incidents[idx].retentionStatus = .deleted
        save()
        debugLog("[IncidentHistory] Deleted local data for incident \(id)")
    }

    // MARK: - Persistence

    private func save() {
        do {
            let data = try JSONEncoder().encode(incidents)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            debugLog("[IncidentHistory] Failed to encode incidents for persistence: \(error.localizedDescription)")
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([IncidentRecord].self, from: data) {
            incidents = decoded
        }
    }
}
