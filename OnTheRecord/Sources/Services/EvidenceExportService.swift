import Foundation
import CryptoKit
import UIKit

/// Generates tamper-proof evidence export packages for legal proceedings.
///
/// The export bundle includes encrypted video chunks, location trail (GPX),
/// chain-of-custody PDF, metadata JSON, and a SHA-256 manifest of all files.
class EvidenceExportService {
    static let shared = EvidenceExportService()

    struct ExportPackage {
        let zipURL: URL
        let manifestHash: String
        let fileCount: Int
        let totalSize: Int64
    }

    struct ExportOptions {
        var includeDecryptedVideo: Bool = false
        var includeLocationTrail: Bool = true
        var includeTranscript: Bool = true
        var includeDepthData: Bool = true
        var includePDFReport: Bool = true
    }

    /// Generate evidence export for an incident.
    func exportEvidence(
        incidentID: String,
        options: ExportOptions = ExportOptions(),
        locationHistory: [Location] = [],
        transcriptText: String? = nil
    ) async throws -> ExportPackage {
        let exportDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("evidence_export_\(incidentID)")

        // Clean up any previous export
        try? FileManager.default.removeItem(at: exportDir)
        try FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)

        var manifest: [(filename: String, sha256: String, size: Int64)] = []

        // 1. Copy encrypted chunks
        let chunksDir = Self.pendingUploadsDirectory(for: incidentID)
        if FileManager.default.fileExists(atPath: chunksDir.path) {
            let chunkFiles = try FileManager.default.contentsOfDirectory(
                at: chunksDir,
                includingPropertiesForKeys: [.fileSizeKey]
            )
            let evidenceChunksDir = exportDir.appendingPathComponent("chunks", isDirectory: true)
            try FileManager.default.createDirectory(at: evidenceChunksDir, withIntermediateDirectories: true)

            for file in chunkFiles {
                let dest = evidenceChunksDir.appendingPathComponent(file.lastPathComponent)
                try FileManager.default.copyItem(at: file, to: dest)
                let data = try Data(contentsOf: dest)
                let hash = SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
                let size = Int64(data.count)
                manifest.append((file.lastPathComponent, hash, size))
            }
        }

        // 2. Location trail (GPX format)
        if options.includeLocationTrail && !locationHistory.isEmpty {
            let gpx = generateGPX(locations: locationHistory, incidentID: incidentID)
            let gpxURL = exportDir.appendingPathComponent("location_trail.gpx")
            try gpx.write(to: gpxURL, atomically: true, encoding: .utf8)
            let data = try Data(contentsOf: gpxURL)
            let hash = SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
            manifest.append(("location_trail.gpx", hash, Int64(data.count)))
        }

        // 3. Transcript
        if options.includeTranscript, let transcript = transcriptText {
            let transcriptURL = exportDir.appendingPathComponent("transcript.txt")
            try transcript.write(to: transcriptURL, atomically: true, encoding: .utf8)
            let data = try Data(contentsOf: transcriptURL)
            let hash = SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
            manifest.append(("transcript.txt", hash, Int64(data.count)))
        }

        // 4. Metadata JSON
        let metadata = generateMetadata(incidentID: incidentID, manifest: manifest)
        let metadataURL = exportDir.appendingPathComponent("metadata.json")
        try metadata.write(to: metadataURL, atomically: true, encoding: .utf8)
        let metaData = try Data(contentsOf: metadataURL)
        let metaHash = SHA256.hash(data: metaData).compactMap { String(format: "%02x", $0) }.joined()
        manifest.append(("metadata.json", metaHash, Int64(metaData.count)))

        // 5. PDF Report (chain-of-custody via IncidentSummaryService)
        if options.includePDFReport {
            let locationEntries = locationHistory.map {
                IncidentSummaryService.IncidentSummary.LocationEntry(
                    timestamp: $0.timestamp,
                    latitude: $0.latitude,
                    longitude: $0.longitude
                )
            }
            let summary = IncidentSummaryService.IncidentSummary(
                incidentID: incidentID,
                startTime: Date(),
                endTime: Date(),
                duration: 0,
                locations: locationEntries,
                chunkCount: manifest.filter { $0.filename.hasSuffix(".iwc") }.count,
                totalDataSize: manifest.reduce(0) { $0 + $1.size },
                destinations: [],
                contacts: [],
                deviceInfo: IncidentSummaryService.IncidentSummary.DeviceInfo(
                    name: UIDevice.current.name,
                    model: UIDevice.current.model,
                    osVersion: UIDevice.current.systemVersion
                ),
                signingPublicKeyFingerprint: nil
            )
            if let pdfData = IncidentSummaryService.generatePDF(from: summary) {
                let pdfURL = exportDir.appendingPathComponent("incident_report.pdf")
                try pdfData.write(to: pdfURL)
                let hash = SHA256.hash(data: pdfData).compactMap { String(format: "%02x", $0) }.joined()
                manifest.append(("incident_report.pdf", hash, Int64(pdfData.count)))
            }
        }

        // 6. Audio Enhancement (optional enhanced copies alongside originals)
        if AudioEnhancementService.shared.config.isEnabled {
            let chunksDir = exportDir.appendingPathComponent("chunks", isDirectory: true)
            if FileManager.default.fileExists(atPath: chunksDir.path) {
                let enhancedDir = exportDir.appendingPathComponent("enhanced", isDirectory: true)
                try FileManager.default.createDirectory(at: enhancedDir, withIntermediateDirectories: true)

                let chunkFiles = try FileManager.default.contentsOfDirectory(
                    at: chunksDir,
                    includingPropertiesForKeys: nil
                )

                for file in chunkFiles {
                    let outputURL = enhancedDir.appendingPathComponent(file.lastPathComponent)
                    do {
                        try await AudioEnhancementService.shared.enhanceAudioFile(
                            inputURL: file,
                            outputURL: outputURL
                        )
                        let data = try Data(contentsOf: outputURL)
                        let hash = SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
                        let size = Int64(data.count)
                        manifest.append(("enhanced/\(file.lastPathComponent)", hash, size))
                        debugLog("[EvidenceExport] Enhanced audio created: enhanced/\(file.lastPathComponent)")
                    } catch {
                        debugLog("[EvidenceExport] Audio enhancement failed for \(file.lastPathComponent): \(error.localizedDescription)")
                    }
                }
            }
        }

        // 7. Timestamp anchor chain
        if let anchorData = try? await TimestampAnchorService.shared.exportAnchors(incidentID: incidentID) {
            let anchorURL = exportDir.appendingPathComponent("timestamp_anchors.json")
            try? anchorData.write(to: anchorURL)
            let anchorHash = SHA256.hash(data: anchorData).compactMap { String(format: "%02x", $0) }.joined()
            manifest.append(("timestamp_anchors.json", anchorHash, Int64(anchorData.count)))
            debugLog("[EvidenceExport] Timestamp anchor chain added (\(anchorData.count) bytes)")
        }

        // 8. Generate manifest file
        let manifestContent = generateManifest(entries: manifest, incidentID: incidentID)
        let manifestURL = exportDir.appendingPathComponent("MANIFEST.sha256")
        try manifestContent.write(to: manifestURL, atomically: true, encoding: .utf8)

        // 9. Create ZIP archive via NSFileCoordinator
        let zipURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("OnTheRecord_Evidence_\(incidentID).zip")
        try? FileManager.default.removeItem(at: zipURL)

        let coordinator = NSFileCoordinator()
        var zipError: NSError?
        coordinator.coordinate(readingItemAt: exportDir, options: .forUploading, error: &zipError) { zipTempURL in
            try? FileManager.default.copyItem(at: zipTempURL, to: zipURL)
        }

        if let error = zipError {
            throw error
        }

        // Calculate overall hash of the zip
        let zipData = try Data(contentsOf: zipURL)
        let overallHash = SHA256.hash(data: zipData).compactMap { String(format: "%02x", $0) }.joined()

        // Clean up export directory
        try? FileManager.default.removeItem(at: exportDir)

        return ExportPackage(
            zipURL: zipURL,
            manifestHash: overallHash,
            fileCount: manifest.count,
            totalSize: Int64(zipData.count)
        )
    }

    // MARK: - GPX Generation

    private func generateGPX(locations: [Location], incidentID: String) -> String {
        let isoFormatter = ISO8601DateFormatter()
        var gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="OnTheRecord"
             xmlns="http://www.topografix.com/GPX/1/1">
          <metadata>
            <name>OnTheRecord Evidence Trail</name>
            <desc>Location trail for incident \(incidentID)</desc>
            <time>\(isoFormatter.string(from: Date()))</time>
          </metadata>
          <trk>
            <name>\(incidentID)</name>
            <trkseg>
        """

        for location in locations {
            gpx += """
                  <trkpt lat="\(location.latitude)" lon="\(location.longitude)">
                    <ele>\(location.altitude ?? 0)</ele>
                    <time>\(isoFormatter.string(from: location.timestamp))</time>
                    <hdop>\(location.accuracy)</hdop>
                  </trkpt>
            """
        }

        gpx += """
            </trkseg>
          </trk>
        </gpx>
        """

        return gpx
    }

    // MARK: - Metadata JSON

    private func generateMetadata(
        incidentID: String,
        manifest: [(filename: String, sha256: String, size: Int64)]
    ) -> String {
        let device = UIDevice.current
        let metadata: [String: Any] = [
            "format_version": "1.0",
            "app_name": "OnTheRecord",
            "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0",
            "incident_id": incidentID,
            "export_timestamp": ISO8601DateFormatter().string(from: Date()),
            "device": [
                "name": device.name,
                "model": device.model,
                "system_version": device.systemVersion,
                "identifier": device.identifierForVendor?.uuidString ?? "unknown"
            ],
            "files": manifest.map { [
                "filename": $0.filename,
                "sha256": $0.sha256,
                "size_bytes": $0.size
            ] }
        ]

        if let data = try? JSONSerialization.data(withJSONObject: metadata, options: .prettyPrinted) {
            return String(data: data, encoding: .utf8) ?? "{}"
        }
        return "{}"
    }

    // MARK: - Manifest

    private func generateManifest(
        entries: [(filename: String, sha256: String, size: Int64)],
        incidentID: String
    ) -> String {
        var manifest = "# OnTheRecord Evidence Manifest\n"
        manifest += "# Incident: \(incidentID)\n"
        manifest += "# Generated: \(ISO8601DateFormatter().string(from: Date()))\n"
        manifest += "# Format: SHA256  FILENAME  SIZE\n\n"

        for entry in entries {
            manifest += "\(entry.sha256)  \(entry.filename)  \(entry.size)\n"
        }

        return manifest
    }

    // MARK: - Helpers

    static func pendingUploadsDirectory(for incidentID: String) -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("OnTheRecord", isDirectory: true)
            .appendingPathComponent("PendingUploads", isDirectory: true)
            .appendingPathComponent(incidentID, isDirectory: true)
    }
}
