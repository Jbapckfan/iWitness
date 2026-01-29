import Foundation
import MultipeerConnectivity
import Combine

/// Manages P2P "Witness Beacon" functionality
/// Allows devices to offload encrypted chunks to nearby devices (Witnesses)
/// and receive chunks from others to upload later.
class WitnessBeaconService: NSObject, ObservableObject {
    static let shared = WitnessBeaconService()
    
    // MARK: - Configuration
    private let serviceType = "witness-beacon" // Must be same on all devices
    private let myPeerID = MCPeerID(displayName: UIDevice.current.name)
    
    // MARK: - Published State
    @Published var connectedPeers: [MCPeerID] = []
    @Published var isAdvertising = false
    @Published var isBrowsing = false
    @Published var receivedChunksCount = 0
    @Published var sentChunksCount = 0
    
    // MARK: - Private State
    private var serviceAdvertiser: MCNearbyServiceAdvertiser?
    private var serviceBrowser: MCNearbyServiceBrowser?
    private var session: MCSession?
    
    private var uploadService: UploadService?
    
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
    
    // MARK: - Data Transmission
    
    func sendChunk(url: URL, metadata: ChunkMetadata) {
        guard !connectedPeers.isEmpty, let session = session else { return }
        
        // We can send to all connected witnesses for redundancy
        // Logic: Send file resource
        
        for peer in connectedPeers {
            debugLog("[WitnessBeacon] Sending chunk \(metadata.chunkNumber) to \(peer.displayName)")
            
            // 1. Send Metadata Header first (Reliable)
            if let headerData = try? JSONEncoder().encode(metadata) {
                try? session.send(headerData, toPeers: [peer], with: .reliable)
            }
            
            // 2. Send File payload (Resource)
            // Use resource for large files
            let chunkName = "chunk_\(metadata.incidentID)_\(metadata.chunkNumber)"
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
}

// MARK: - MCSessionDelegate
extension WitnessBeaconService: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        debugLog("[WitnessBeacon] Peer \(peerID.displayName) changed state to \(state.rawValue)")
        
        DispatchQueue.main.async {
            self.connectedPeers = session.connectedPeers
        }
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        // Received small data (Metadata usually)
        // For MVP, if we receive metadata, we might prepare to receive the resource
        debugLog("[WitnessBeacon] Received data from \(peerID.displayName) (\(data.count) bytes)")
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
        
        // This file is likely in a temp directory that will be wiped. Move it immediately!
        saveReceivedEvidence(from: localURL, name: resourceName)
    }
    
    private func saveReceivedEvidence(from url: URL, name: String) {
        // Move to our upload queue
        // We received an .iwc (EncryptedChunk) probably.
        
        let fileManager = FileManager.default
        guard let supportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        
        // Create "WitnessedEvidence" directory
        let witnessedDir = supportDir.appendingPathComponent("WitnessedEvidence")
        try? fileManager.createDirectory(at: witnessedDir, withIntermediateDirectories: true)
        
        let destinationURL = witnessedDir.appendingPathComponent(name + ".iwc")
        
        do {
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.moveItem(at: url, to: destinationURL)
            
            // Queue for upload!
            // We act as a mule. We don't know the content, but we upload it.
            // Parse info from filename if possible or just queue it as "Unknown Incident"
            // Actually, we ideally want to parse the header to get the Incident ID
            
            // For now, blindly queue
            Task { @MainActor in
                self.receivedChunksCount += 1
                // Trigger upload service to pick this up
                // (Feature: "Mule Mode" in UploadService to upload foreign chunks)
                self.uploadService?.queueForeignChunk(url: destinationURL)
            }
            
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
