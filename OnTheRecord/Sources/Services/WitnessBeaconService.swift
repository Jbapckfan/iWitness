import Foundation
import MultipeerConnectivity
import Combine

// MARK: - Time Sync Protocol Types

enum BeaconMessageType: String, Codable {
    case chunkData
    case chunkReceipt
    case syncRequest      // "I want to start recording, what's your time?"
    case syncResponse     // "My time is X, ready to record"
    case syncStart        // "Start recording at T=X"
    case syncStop         // "Stop recording"
}

struct SyncMessage: Codable {
    let type: BeaconMessageType
    let senderDeviceID: String
    let incidentID: String?
    let timestamp: Date       // sender's current time
    let scheduledStart: Date? // for syncStart: when to begin
    let payload: Data?        // for chunkData
    let chunkNumber: Int?     // for chunk metadata
}

/// Manages P2P "Witness Beacon" functionality
/// Allows devices to offload encrypted chunks to nearby devices (Witnesses)
/// and receive chunks from others to upload later.
class WitnessBeaconService: NSObject, ObservableObject {
    static let shared = WitnessBeaconService()
    
    // MARK: - Configuration
    private let serviceType = "witness-beacon" // Must be same on all devices
    private let myPeerID = MCPeerID(displayName: UIDevice.current.name)
    private let deviceID: String = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString

    // MARK: - Published State
    @Published var connectedPeers: [MCPeerID] = []
    @Published var isAdvertising = false
    @Published var isBrowsing = false
    @Published var receivedChunksCount = 0
    @Published var sentChunksCount = 0

    // MARK: - Time Sync State
    @Published var connectedWitnesses: Int = 0
    @Published var isSyncLeader: Bool = false
    @Published var syncedIncidentID: String?

    /// Called when coordinated recording should start
    var onCoordinatedRecordStart: ((String) -> Void)?
    var onStopCommand: (() -> Void)?
    
    // MARK: - Private State
    private var serviceAdvertiser: MCNearbyServiceAdvertiser?
    private var serviceBrowser: MCNearbyServiceBrowser?
    private var session: MCSession?
    
    private var uploadService: UploadService?

    /// Stores pending chunk metadata received via P2P data messages, keyed by peer display name
    private var pendingChunkHeaders: [String: P2PMessage] = []

    // MARK: - Initialization
    override init() {
        super.init()
        setupSession()
    }
    
    func configure(uploadService: UploadService) {
        self.uploadService = uploadService
    }
    
    private func setupSession() {
        // Require encryption for all P2P traffic
        session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        session?.delegate = self
    }
    
    // MARK: - Mode Control
    
    /// Start advertising availability to receive evidence (Witness Mode)
    /// OR advertising existence to offload evidence (Recorder Mode)
    /// For simplicity in MVP, everyone is both a browser and advertiser,
    /// or we switch based on state.
    ///
    /// Strategy:
    /// - Recorders ADVERTISE (I have data)
    /// - Witnesses BROWSE (I can help)
    /// OR vice versa. Multipeer standard usually:
    /// - Server (Host) Advertises
    /// - Client (Joiner) Browses
    ///
    /// HERE: "Witnesses" are the infrastructure. "Recorders" connect to them.
    /// So Witnesses (Idle users) ADVERTISE. Recorders BROWSE.
    
    func startWitnessMode() {
        // I am a witness. I advertise that I can accept evidence.
        debugLog("[WitnessBeacon] Starting Witness Mode (Advertising)")
        
        serviceAdvertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: ["role": "witness"], serviceType: serviceType)
        serviceAdvertiser?.delegate = self
        serviceAdvertiser?.startAdvertisingPeer()
        
        isAdvertising = true
    }
    
    func startBroadcastingMode() {
        // I am recording. I look for witnesses to offload to.
        debugLog("[WitnessBeacon] Starting Broadcast Mode (Browsing)")
        
        serviceBrowser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
        serviceBrowser?.delegate = self
        serviceBrowser?.startBrowsingForPeers()
        
        isBrowsing = true
    }
    
    func stopAll() {
        serviceAdvertiser?.stopAdvertisingPeer()
        serviceBrowser?.stopBrowsingForPeers()
        session?.disconnect()
        
        isAdvertising = false
        isBrowsing = false
        connectedPeers.removeAll()
    }
    
    // MARK: - P2P Message Types

    private enum P2PMessageType: String, Codable {
        case chunkHeader
        case receiptConfirmation
    }

    private struct P2PMessage: Codable {
        let type: P2PMessageType
        let incidentID: String
        let chunkNumber: Int
        let timestamp: Date?
    }

    // MARK: - Data Transmission

    func sendChunk(url: URL, metadata: ChunkMetadata) {
        guard !connectedPeers.isEmpty, let session = session else { return }

        for peer in connectedPeers {
            debugLog("[WitnessBeacon] Sending chunk \(metadata.chunkNumber) to \(peer.displayName)")

            // Send a JSON header message first so the receiver knows incident ID and chunk number
            let headerMessage = P2PMessage(
                type: .chunkHeader,
                incidentID: metadata.incidentID,
                chunkNumber: metadata.chunkNumber,
                timestamp: metadata.timestamp
            )
            if let headerData = try? JSONEncoder().encode(headerMessage) {
                do {
                    try session.send(headerData, toPeers: [peer], with: .reliable)
                } catch {
                    debugLog("[WitnessBeacon] Failed to send header to peer: \(error.localizedDescription)")
                }
            }

            // Send the resource with incident ID and chunk number encoded in the name
            let chunkName = "\(metadata.incidentID)_chunk_\(String(format: "%05d", metadata.chunkNumber))"
            session.sendResource(at: url, withName: chunkName, toPeer: peer) { error in
                if let error = error {
                    debugLog("[WitnessBeacon] Error sending chunk to \(peer.displayName): \(error)")
                } else {
                    debugLog("[WitnessBeacon] Finished sending chunk to \(peer.displayName)")
                    DispatchQueue.main.async {
                        self.sentChunksCount += 1
                    }
                }
            }
        }
    }

    /// Sends chunk to connected peers. Returns false if no peers are connected.
    func sendChunkWithConfirmation(url: URL, metadata: ChunkMetadata) -> Bool {
        guard !connectedPeers.isEmpty, session != nil else { return false }
        sendChunk(url: url, metadata: metadata)
        return true
    }

    // MARK: - Coordinated Multi-Device Recording

    /// Initiates a coordinated recording across all connected peers.
    /// The calling device becomes the sync leader and broadcasts a sync request.
    func initiateCoordinatedRecording(incidentID: String) {
        isSyncLeader = true
        syncedIncidentID = incidentID

        // Send sync request to all connected peers
        let message = SyncMessage(
            type: .syncRequest,
            senderDeviceID: deviceID,
            incidentID: incidentID,
            timestamp: Date(),
            scheduledStart: nil,
            payload: nil,
            chunkNumber: nil
        )

        broadcastMessage(message)
    }

    private func broadcastMessage(_ message: SyncMessage) {
        guard let data = try? JSONEncoder().encode(message) else {
            debugLog("[WitnessBeacon] Failed to encode sync message")
            return
        }

        if let session = session, !session.connectedPeers.isEmpty {
            do {
                try session.send(data, toPeers: session.connectedPeers, with: .reliable)
            } catch {
                debugLog("[WitnessBeacon] Failed to broadcast sync message: \(error.localizedDescription)")
            }
        }
    }

    private func handleSyncMessage(_ message: SyncMessage, from peer: MCPeerID) {
        switch message.type {
        case .syncRequest:
            // Respond with our time
            let response = SyncMessage(
                type: .syncResponse,
                senderDeviceID: deviceID,
                incidentID: message.incidentID,
                timestamp: Date(),
                scheduledStart: nil,
                payload: nil,
                chunkNumber: nil
            )
            broadcastMessage(response)
            syncedIncidentID = message.incidentID

        case .syncResponse:
            // Leader collects responses, then sends coordinated start
            if isSyncLeader {
                // Schedule start 2 seconds from now to allow for latency
                let startTime = Date().addingTimeInterval(2.0)
                let startMsg = SyncMessage(
                    type: .syncStart,
                    senderDeviceID: deviceID,
                    incidentID: syncedIncidentID,
                    timestamp: Date(),
                    scheduledStart: startTime,
                    payload: nil,
                    chunkNumber: nil
                )
                broadcastMessage(startMsg)

                // Also start our own recording at the scheduled time
                scheduleRecordingStart(at: startTime, incidentID: syncedIncidentID ?? "unknown")
            }

        case .syncStart:
            // Follower: start recording at the scheduled time
            if let startTime = message.scheduledStart {
                scheduleRecordingStart(at: startTime, incidentID: message.incidentID ?? "unknown")
            }

        case .syncStop:
            onStopCommand?()

        default:
            break
        }
    }

    private func scheduleRecordingStart(at date: Date, incidentID: String) {
        let delay = date.timeIntervalSinceNow
        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.onCoordinatedRecordStart?(incidentID)
            }
        } else {
            onCoordinatedRecordStart?(incidentID)
        }
    }
}

// MARK: - MCSessionDelegate
extension WitnessBeaconService: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        debugLog("[WitnessBeacon] Peer \(peerID.displayName) changed state to \(state.rawValue)")

        DispatchQueue.main.async {
            self.connectedPeers = session.connectedPeers
            self.connectedWitnesses = session.connectedPeers.count
        }
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        debugLog("[WitnessBeacon] Received data from \(peerID.displayName) (\(data.count) bytes)")

        // Try to decode as SyncMessage first (coordinated recording protocol)
        if let syncMsg = try? JSONDecoder().decode(SyncMessage.self, from: data) {
            Task { @MainActor in
                handleSyncMessage(syncMsg, from: peerID)
            }
            return
        }

        // Fall back to existing P2P chunk offloading message
        guard let message = try? JSONDecoder().decode(P2PMessage.self, from: data) else {
            debugLog("[WitnessBeacon] Could not decode P2P message from \(peerID.displayName)")
            return
        }

        switch message.type {
        case .chunkHeader:
            // Store the header so we can use it when the resource finishes arriving
            pendingChunkHeaders[peerID.displayName] = message
            debugLog("[WitnessBeacon] Stored chunk header for incident \(message.incidentID) chunk \(message.chunkNumber) from \(peerID.displayName)")

        case .receiptConfirmation:
            debugLog("[WitnessBeacon] Received receipt confirmation from \(peerID.displayName) for incident \(message.incidentID) chunk \(message.chunkNumber)")
        }
    }
    
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        // Stream
    }
    
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        debugLog("[WitnessBeacon] Started receiving resource: \(resourceName)")
    }
    
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        guard let localURL = localURL, error == nil else {
            debugLog("[WitnessBeacon] Error receiving resource: \(String(describing: error))")
            return
        }

        debugLog("[WitnessBeacon] Finished receiving resource: \(resourceName) at \(localURL)")

        // Extract incident ID and chunk number from the header message or fall back to resource name
        let incidentID: String
        let chunkNumber: Int

        if let header = pendingChunkHeaders.removeValue(forKey: peerID.displayName) {
            incidentID = header.incidentID
            chunkNumber = header.chunkNumber
        } else {
            // Fallback: parse from resource name format "{incidentID}_chunk_{number}"
            let parts = resourceName.split(separator: "_chunk_")
            incidentID = parts.count >= 1 ? String(parts[0]) : "unknown"
            chunkNumber = parts.count >= 2 ? (Int(parts[1]) ?? 0) : 0
            debugLog("[WitnessBeacon] No header found for resource from \(peerID.displayName), parsed from name: incident=\(incidentID) chunk=\(chunkNumber)")
        }

        // Save with proper naming
        saveReceivedEvidence(from: localURL, incidentID: incidentID, chunkNumber: chunkNumber)

        // Send receipt confirmation back to the sender
        sendReceiptConfirmation(to: peerID, session: session, incidentID: incidentID, chunkNumber: chunkNumber)
    }

    private func sendReceiptConfirmation(to peer: MCPeerID, session: MCSession, incidentID: String, chunkNumber: Int) {
        let confirmation = P2PMessage(
            type: .receiptConfirmation,
            incidentID: incidentID,
            chunkNumber: chunkNumber,
            timestamp: Date()
        )
        if let data = try? JSONEncoder().encode(confirmation) {
            do {
                try session.send(data, toPeers: [peer], with: .reliable)
                debugLog("[WitnessBeacon] Sent receipt confirmation to \(peer.displayName) for chunk \(chunkNumber)")
            } catch {
                debugLog("[WitnessBeacon] Failed to send receipt confirmation to \(peer.displayName): \(error.localizedDescription)")
            }
        }
    }

    private func saveReceivedEvidence(from url: URL, incidentID: String, chunkNumber: Int) {
        let fileManager = FileManager.default
        guard let supportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }

        // Create "WitnessedEvidence/{incidentID}" directory
        let witnessedDir = supportDir
            .appendingPathComponent("WitnessedEvidence")
            .appendingPathComponent(incidentID)
        try? fileManager.createDirectory(at: witnessedDir, withIntermediateDirectories: true)

        // Save with proper naming: {incidentID}_chunk_{number}.iwc
        let filename = "\(incidentID)_chunk_\(String(format: "%05d", chunkNumber)).iwc"
        let destinationURL = witnessedDir.appendingPathComponent(filename)

        do {
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.moveItem(at: url, to: destinationURL)

            Task { @MainActor in
                self.receivedChunksCount += 1
                self.uploadService?.queueForeignChunk(url: destinationURL)
            }

            debugLog("[WitnessBeacon] Saved witnessed chunk: \(filename)")
        } catch {
            debugLog("[WitnessBeacon] Failed to move received evidence: \(error)")
        }
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate
extension WitnessBeaconService: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // Auto-accept invitations if we are in Witness Mode
        debugLog("[WitnessBeacon] Accepting invitation from \(peerID.displayName)")
        invitationHandler(true, self.session)
    }
}

// MARK: - MCNearbyServiceBrowserDelegate
extension WitnessBeaconService: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        // Found a witness. Auto-invite them!
        debugLog("[WitnessBeacon] Found witness: \(peerID.displayName). Inviting...")
        browser.invitePeer(peerID, to: self.session!, withContext: nil, timeout: 10)
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        debugLog("[WitnessBeacon] Lost witness: \(peerID.displayName)")
    }
}
