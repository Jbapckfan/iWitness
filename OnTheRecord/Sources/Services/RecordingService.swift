import Foundation
import AVFoundation
import CoreLocation
import Combine
import Photos
import UIKit
import LocalAuthentication

import CryptoKit

// MARK: - Vault Manager
class VaultManager: ObservableObject {
    static let shared = VaultManager()
    
    @Published var isAuthenticated = false
    @Published var vaultFiles: [URL] = []
    
    private let fileManager = FileManager.default
    private let vaultDirectoryName = "Vault"
    private let keyTag = "com.ontherecord.vault.encryptionkey"
    
    // Encryption key (lazily loaded from Keychain)
    private lazy var encryptionKey: SymmetricKey = {
        if let existingKey = loadKeyFromKeychain() {
            return existingKey
        }
        let newKey = SymmetricKey(size: .bits256)
        saveKeyToKeychain(newKey)
        return newKey
    }()
    
    var vaultURL: URL? {
        guard let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        return documents.appendingPathComponent(vaultDirectoryName, isDirectory: true)
    }
    
    private init() {
        createVaultDirectoryIfNeeded()
        // Do not block init with IO
        Task {
            await refreshFiles()
        }
    }
    
    private func createVaultDirectoryIfNeeded() {
        guard let url = vaultURL else { return }
        if !fileManager.fileExists(atPath: url.path) {
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: [
                .protectionKey: FileProtectionType.completeUnlessOpen
            ])
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            var mutableUrl = url
            try? mutableUrl.setResourceValues(resourceValues)
        }
    }
    
    @MainActor
    func refreshFiles() async {
        guard let url = vaultURL else { return }
        
        let sortedFiles = await Task.detached(priority: .userInitiated) { () -> [URL] in
            let fileManager = FileManager.default
            do {
                let fileURLs = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles)
                return fileURLs.sorted {
                    let date1 = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                    let date2 = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                    return date1 > date2
                }
            } catch {
                debugLog("[VaultManager] Error listing files: \(error)")
                return []
            }
        }.value
        
        self.vaultFiles = sortedFiles
    }
    
    // MARK: - Encrypted File Operations
    
    func moveFileToVault(from tempURL: URL) -> Bool {
        guard let vault = vaultURL else { return false }
        
        // Encrypt file before storing
        let encryptedFilename = tempURL.deletingPathExtension().lastPathComponent + ".enc"
        let destinationURL = vault.appendingPathComponent(encryptedFilename)
        
        do {
            // Read original video data
            let videoData = try Data(contentsOf: tempURL)
            
            // Encrypt with AES-GCM
            let sealedBox = try AES.GCM.seal(videoData, using: encryptionKey)
            guard let encryptedData = sealedBox.combined else {
                debugLog("[VaultManager] Encryption failed - no combined data")
                return false
            }
            
            // Write encrypted data
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try encryptedData.write(to: destinationURL)
            
            // Remove original unencrypted file
            try? fileManager.removeItem(at: tempURL)
            
            Task { @MainActor in
                await refreshFiles()
            }
            return true
        } catch {
            debugLog("[VaultManager] Encryption/Move failed: \(error)")
            return false
        }
    }
    
    func decryptFile(_ encryptedURL: URL) -> URL? {
        do {
            let encryptedData = try Data(contentsOf: encryptedURL)
            let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
            let decryptedData = try AES.GCM.open(sealedBox, using: encryptionKey)
            
            // Write to temp for playback
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
            try decryptedData.write(to: tempURL)
            return tempURL
        } catch {
            debugLog("[VaultManager] Decryption failed: \(error)")
            return nil
        }
    }
    
    func deleteFile(_ url: URL) {
        do {
            try fileManager.removeItem(at: url)
            Task { @MainActor in
                await refreshFiles()
            }
        } catch {
            debugLog("[VaultManager] Delete failed: \(error)")
        }
    }
    
    // MARK: - Keychain Operations
    
    private func saveKeyToKeychain(_ key: SymmetricKey) {
        let keyData = key.withUnsafeBytes { Data($0) }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keyTag,
            kSecAttrAccount as String: "vaultKey",
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemDelete(query as CFDictionary) // Remove existing if any
        SecItemAdd(query as CFDictionary, nil)
    }
    
    private func loadKeyFromKeychain() -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keyTag,
            kSecAttrAccount as String: "vaultKey",
            kSecReturnData as String: true
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let keyData = result as? Data else { return nil }
        return SymmetricKey(data: keyData)
    }
    
    // MARK: - Authentication
    
    func authenticate(completion: @escaping (Bool) -> Void) {
        let context = LAContext()
        var error: NSError?
        
        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            let reason = "Authenticate to access the Secure Vault"
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, authenticationError in
                DispatchQueue.main.async {
                    self.isAuthenticated = success
                    completion(success)
                }
            }
        } else {
            DispatchQueue.main.async {
                self.isAuthenticated = false
                completion(false)
            }
        }
    }
    
    func lock() {
        isAuthenticated = false
    }

    @MainActor
    func handleDuressEntry() {
        // 1. Immediately Lock
        lock()
        
        // 2. Clear known files from memory (decoy mode)
        vaultFiles = []
        
        // 3. Trigger Silent Panic (via AlertService)
        // Note: AlertService is EnvironmentObject usually, but we can access via shared instance if available
        // Or post notification
        NotificationCenter.default.post(name: NSNotification.Name("com.ontherecord.panicTriggered"), object: nil)
        
        debugLog("[VaultManager] Duress PIN entered. Vault locked and decoy mode active.")
    }
}

/// Handles video capture with dual storage:
/// 1. Visible copy in Photos (can be "deleted" by bad actors)
/// 2. Hidden encrypted backup to NAS (survives deletion)
///
/// Supports dual camera recording on compatible devices (iPhone XS+)
class RecordingService: NSObject, ObservableObject {
    // MARK: - Published State

    @MainActor @Published var isRecording = false
    @MainActor @Published var currentChunkNumber = 0
    @MainActor @Published var error: RecordingError?
    @MainActor @Published var savedToPhotos = false
    @MainActor @Published var frontSavedToPhotos = false
    @MainActor @Published var backSavedToPhotos = false
    @MainActor @Published var isDualCameraSupported = false

    // MARK: - Camera Preview Layers (for UI)

    private(set) var frontPreviewLayer: AVCaptureVideoPreviewLayer?
    private(set) var backPreviewLayer: AVCaptureVideoPreviewLayer?

    // Legacy single preview (for fallback)
    var previewLayer: AVCaptureVideoPreviewLayer? {
        return backPreviewLayer ?? frontPreviewLayer
    }

    // MARK: - Configuration

    private let chunkDuration: TimeInterval = 2.0
    private var currentQuality: AppState.VideoQuality = .high
    @Published var currentCameraPosition: AVCaptureDevice.Position = .front

    // MARK: - AVFoundation Components

    private var multiCamSession: AVCaptureMultiCamSession?
    private var singleCamSession: AVCaptureSession?

    // Dual camera outputs
    private var frontMovieOutput: AVCaptureMovieFileOutput?
    private var backMovieOutput: AVCaptureMovieFileOutput?

    // Single camera fallback
    private var movieFileOutput: AVCaptureMovieFileOutput?

    // For encrypted NAS backup (uses back camera or single camera)
    private var videoOutput: AVCaptureVideoDataOutput?
    private var audioOutput: AVCaptureAudioDataOutput?

    // MARK: - Recording Components

    private var chunkWriter: ChunkWriter?
    private var uploadService: UploadService?
    private var liveStreamService: LiveStreamService?
    private let encryptionService = EncryptionService()
    private let locationService = LocationService()
    
    // Thermal state monitoring
    private var thermalStateObservation: NSObjectProtocol?

    // MARK: - Session Management

    private var currentIncidentID: String?
    private var chunkTimer: Timer?
    private let sessionQueue = DispatchQueue(label: "com.ontherecord.session", qos: .userInitiated)
    private let processingQueue = DispatchQueue(label: "com.ontherecord.processing", qos: .userInitiated)

    // Local video file URLs
    private var frontVideoURL: URL?
    private var backVideoURL: URL?
    private var localVideoURL: URL? // For single camera fallback

    // Track completion of dual recording
    private var frontRecordingFinished = false
    private var backRecordingFinished = false

    // MARK: - Errors

    enum RecordingError: LocalizedError {
        case cameraNotAvailable
        case cameraAccessDenied
        case microphoneAccessDenied
        case sessionConfigurationFailed
        case photoLibraryAccessDenied
        case multiCamNotSupported

        var errorDescription: String? {
            switch self {
            case .cameraNotAvailable:
                return "Camera is not available"
            case .cameraAccessDenied:
                return "Camera access is required"
            case .microphoneAccessDenied:
                return "Microphone access is required"
            case .sessionConfigurationFailed:
                return "Failed to configure camera"
            case .photoLibraryAccessDenied:
                return "Photo library access is required"
            case .multiCamNotSupported:
                return "Dual camera recording not supported on this device"
            }
        }
    }

    private let shakeService = ShakeGestureService.shared
    private let legalService = LegalComplianceService.shared
    private var cancellables = Set<AnyCancellable>()
    
    // Published event for UI to handle "Superlock" (black screen)
    @MainActor @Published var shouldLockScreen = false

    // MARK: - Initialization

    override init() {
        super.init()
        checkMultiCamSupport()
        startThermalMonitoring()
        setupShakeHandling()
    }
    
    private func setupShakeHandling() {
        // Start monitoring shake immediately (or maybe only when app is active? For safety, always)
        shakeService.startMonitoring()
        
        shakeService.onShakeDetected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.handleShakeEvent()
                }
            }
            .store(in: &cancellables)
    }
    
    @MainActor
    private func handleShakeEvent() {
        debugLog("[RecordingService] Handling Shake Event - Superlock Triggered")
        
        // 1. If not recording, start recording immediately
        if !isRecording {
            Task {
                try? await startRecording(incidentID: UUID().uuidString, quality: .high)
            }
        }
        
        // 2. Signal UI to "Lock" (show black screen / require PIN)
        shouldLockScreen = true
    }
    
    deinit {
        shakeService.stopMonitoring()
        if let observation = thermalStateObservation {
            NotificationCenter.default.removeObserver(observation)
        }
    }

    func configure(uploadService: UploadService, liveStreamService: LiveStreamService) {
        self.uploadService = uploadService
        self.liveStreamService = liveStreamService
    }

    private func checkMultiCamSupport() {
        let supported = AVCaptureMultiCamSession.isMultiCamSupported
        Task { @MainActor in
            self.isDualCameraSupported = supported
        }
    }

    // MARK: - Permissions

    func requestCameraPermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default:
            return false
        }
    }

    func requestMicrophonePermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
    }

    func requestPhotoLibraryPermission() async -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch status {
        case .authorized, .limited:
            return true
        case .notDetermined:
            let newStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            return newStatus == .authorized || newStatus == .limited
        default:
            return false
        }
    }

    // MARK: - Dual Camera Session Setup

    private func setupDualCameraSession() throws {
        guard AVCaptureMultiCamSession.isMultiCamSupported else {
            throw RecordingError.multiCamNotSupported
        }

        let session = AVCaptureMultiCamSession()

        // Get front camera
        guard let frontCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            throw RecordingError.cameraNotAvailable
        }

        // Get back camera
        guard let backCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw RecordingError.cameraNotAvailable
        }

        // Front camera input
        let frontInput = try AVCaptureDeviceInput(device: frontCamera)
        guard session.canAddInput(frontInput) else {
            throw RecordingError.sessionConfigurationFailed
        }
        session.addInputWithNoConnections(frontInput)

        // Back camera input
        let backInput = try AVCaptureDeviceInput(device: backCamera)
        guard session.canAddInput(backInput) else {
            throw RecordingError.sessionConfigurationFailed
        }
        session.addInputWithNoConnections(backInput)

        // Audio input (shared)
        if let audioDevice = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: audioDevice),
           session.canAddInput(audioInput) {
            session.addInputWithNoConnections(audioInput)

            // Audio input added - will be automatically connected to movie outputs
        }

        // Front movie output
        let frontOutput = AVCaptureMovieFileOutput()
        frontOutput.maxRecordedDuration = CMTime(seconds: 3600, preferredTimescale: 1)
        guard session.canAddOutput(frontOutput) else {
            throw RecordingError.sessionConfigurationFailed
        }
        session.addOutputWithNoConnections(frontOutput)
        self.frontMovieOutput = frontOutput

        // Back movie output
        let backOutput = AVCaptureMovieFileOutput()
        backOutput.maxRecordedDuration = CMTime(seconds: 3600, preferredTimescale: 1)
        guard session.canAddOutput(backOutput) else {
            throw RecordingError.sessionConfigurationFailed
        }
        session.addOutputWithNoConnections(backOutput)
        self.backMovieOutput = backOutput

        // Connect front camera to front output
        if let frontVideoPort = frontInput.ports(for: .video, sourceDeviceType: .builtInWideAngleCamera, sourceDevicePosition: .front).first {
            let frontConnection = AVCaptureConnection(inputPorts: [frontVideoPort], output: frontOutput)
            if session.canAddConnection(frontConnection) {
                session.addConnection(frontConnection)
            }
        }

        // Connect back camera to back output
        if let backVideoPort = backInput.ports(for: .video, sourceDeviceType: .builtInWideAngleCamera, sourceDevicePosition: .back).first {
            let backConnection = AVCaptureConnection(inputPorts: [backVideoPort], output: backOutput)
            if session.canAddConnection(backConnection) {
                session.addConnection(backConnection)
            }
        }

        // Connect audio to both outputs
        if let audioDevice = AVCaptureDevice.default(for: .audio),
           let audioInput = session.inputs.compactMap({ $0 as? AVCaptureDeviceInput }).first(where: { $0.device == audioDevice }),
           let audioPort = audioInput.ports(for: .audio, sourceDeviceType: nil, sourceDevicePosition: .unspecified).first {

            let frontAudioConnection = AVCaptureConnection(inputPorts: [audioPort], output: frontOutput)
            if session.canAddConnection(frontAudioConnection) {
                session.addConnection(frontAudioConnection)
            }

            let backAudioConnection = AVCaptureConnection(inputPorts: [audioPort], output: backOutput)
            if session.canAddConnection(backAudioConnection) {
                session.addConnection(backAudioConnection)
            }
        }

        // Add Video Data Output for NAS Backup/Streaming (Attach to BACK camera)
        let videoOut = AVCaptureVideoDataOutput()
        videoOut.setSampleBufferDelegate(self, queue: processingQueue)
        videoOut.alwaysDiscardsLateVideoFrames = true
        guard session.canAddOutput(videoOut) else {
            throw RecordingError.sessionConfigurationFailed
        }
        session.addOutputWithNoConnections(videoOut)
        self.videoOutput = videoOut

        if let backVideoPort = backInput.ports(for: .video, sourceDeviceType: .builtInWideAngleCamera, sourceDevicePosition: .back).first {
            let backDataConnection = AVCaptureConnection(inputPorts: [backVideoPort], output: videoOut)
            if session.canAddConnection(backDataConnection) {
                session.addConnection(backDataConnection)
            }
        }

        // Add Audio Data Output for NAS Backup/Streaming
        let audioOut = AVCaptureAudioDataOutput()
        audioOut.setSampleBufferDelegate(self, queue: processingQueue)
        guard session.canAddOutput(audioOut) else {
            throw RecordingError.sessionConfigurationFailed
        }
        session.addOutputWithNoConnections(audioOut)
        self.audioOutput = audioOut

        if let audioDevice = AVCaptureDevice.default(for: .audio),
           let audioInput = session.inputs.compactMap({ $0 as? AVCaptureDeviceInput }).first(where: { $0.device == audioDevice }),
           let audioPort = audioInput.ports(for: .audio, sourceDeviceType: nil, sourceDevicePosition: .unspecified).first {
            
            let audioDataConnection = AVCaptureConnection(inputPorts: [audioPort], output: audioOut)
            if session.canAddConnection(audioDataConnection) {
                session.addConnection(audioDataConnection)
            }
        }

        // Create preview layers
        let frontPreview = AVCaptureVideoPreviewLayer(sessionWithNoConnection: session)
        frontPreview.videoGravity = .resizeAspectFill
        if let frontVideoPort = frontInput.ports(for: .video, sourceDeviceType: .builtInWideAngleCamera, sourceDevicePosition: .front).first {
            let previewConnection = AVCaptureConnection(inputPort: frontVideoPort, videoPreviewLayer: frontPreview)
            if session.canAddConnection(previewConnection) {
                session.addConnection(previewConnection)
            }
        }
        self.frontPreviewLayer = frontPreview

        let backPreview = AVCaptureVideoPreviewLayer(sessionWithNoConnection: session)
        backPreview.videoGravity = .resizeAspectFill
        if let backVideoPort = backInput.ports(for: .video, sourceDeviceType: .builtInWideAngleCamera, sourceDevicePosition: .back).first {
            let previewConnection = AVCaptureConnection(inputPort: backVideoPort, videoPreviewLayer: backPreview)
            if session.canAddConnection(previewConnection) {
                session.addConnection(previewConnection)
            }
        }
        self.backPreviewLayer = backPreview

        self.multiCamSession = session
    }

    // MARK: - Single Camera Session Setup (Fallback)

    private func setupSingleCameraSession() throws {
        let session = AVCaptureSession()
        session.sessionPreset = .high

        // Get front camera (default for documenting interactions)
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
              ?? AVCaptureDevice.default(for: .video) else {
            throw RecordingError.cameraNotAvailable
        }

        // Video input
        let videoInput = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(videoInput) else {
            throw RecordingError.sessionConfigurationFailed
        }
        session.addInput(videoInput)

        // Audio input
        if let audioDevice = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: audioDevice),
           session.canAddInput(audioInput) {
            session.addInput(audioInput)
        }

        // Movie file output (for saving to Photos)
        let movieOut = AVCaptureMovieFileOutput()
        movieOut.maxRecordedDuration = CMTime(seconds: 3600, preferredTimescale: 1)
        if session.canAddOutput(movieOut) {
            session.addOutput(movieOut)
            self.movieFileOutput = movieOut
        }

        // Video data output (for chunk encryption)
        let videoOut = AVCaptureVideoDataOutput()
        videoOut.setSampleBufferDelegate(self, queue: processingQueue)
        videoOut.alwaysDiscardsLateVideoFrames = true
        if session.canAddOutput(videoOut) {
            session.addOutput(videoOut)
            self.videoOutput = videoOut
        }

        // Audio data output (for chunk encryption)
        let audioOut = AVCaptureAudioDataOutput()
        audioOut.setSampleBufferDelegate(self, queue: processingQueue)
        if session.canAddOutput(audioOut) {
            session.addOutput(audioOut)
            self.audioOutput = audioOut
        }

        // Create preview layer
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        self.frontPreviewLayer = preview

        self.singleCamSession = session
    }

    // MARK: - Recording Control

    func startRecording(incidentID: String, quality: AppState.VideoQuality) async throws {
        self.currentIncidentID = incidentID
        self.currentQuality = quality

        // Request photo library permission
        _ = await requestPhotoLibraryPermission()

        // Reset state
        await MainActor.run {
            self.frontRecordingFinished = false
            self.backRecordingFinished = false
            self.frontSavedToPhotos = false
            self.backSavedToPhotos = false
            self.savedToPhotos = false
        }

        // Setup session - try dual camera first, fall back to single
        let useDualCamera = AVCaptureMultiCamSession.isMultiCamSupported

        if useDualCamera {
            if multiCamSession == nil {
                try setupDualCameraSession()
            }
        } else {
            if singleCamSession == nil {
                try setupSingleCameraSession()
            }
        }

        // Initialize chunk writer for NAS backup
        let writer = ChunkWriter(
            incidentID: incidentID,
            chunkDuration: chunkDuration,
            quality: quality,
            encryptionService: encryptionService
        )
        self.chunkWriter = writer
        writer.startNewChunk()
        
        // Check legal compliance (Two-Party Consent laws)
        legalService.checkCompliance()
        debugLog("[RecordingService] Legal Consent Law: \(legalService.currentLaw.rawValue)")

        // Start location tracking
        locationService.startTracking()

        // Create local video file URLs
        let tempDir = FileManager.default.temporaryDirectory

        if useDualCamera {
            frontVideoURL = tempDir.appendingPathComponent("OnTheRecord_\(incidentID)_front.mov")
            backVideoURL = tempDir.appendingPathComponent("OnTheRecord_\(incidentID)_back.mov")
        } else {
            localVideoURL = tempDir.appendingPathComponent("OnTheRecord_\(incidentID).mov")
        }

        // Start capture session and movie recording
        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            if useDualCamera {
                self.multiCamSession?.startRunning()

                // Start recording to both files
                if let frontURL = self.frontVideoURL, let frontOutput = self.frontMovieOutput {
                    try? FileManager.default.removeItem(at: frontURL)
                    frontOutput.startRecording(to: frontURL, recordingDelegate: self)
                }

                if let backURL = self.backVideoURL, let backOutput = self.backMovieOutput {
                    try? FileManager.default.removeItem(at: backURL)
                    backOutput.startRecording(to: backURL, recordingDelegate: self)
                }
            } else {
                self.singleCamSession?.startRunning()

                if let url = self.localVideoURL, let movieOutput = self.movieFileOutput {
                    try? FileManager.default.removeItem(at: url)
                    movieOutput.startRecording(to: url, recordingDelegate: self)
                }
            }
        }

        // Update UI state
        await MainActor.run {
            self.isRecording = true
            self.currentChunkNumber = 0
            self.startChunkTimer()
        }
    }

    func stopRecording() async {
        // Stop chunk timer
        await MainActor.run {
            chunkTimer?.invalidate()
            chunkTimer = nil
        }

        // Finalize current chunk for NAS
        if let writer = chunkWriter, let chunkURL = await writer.finalizeCurrentChunk() {
            await uploadChunk(chunkURL)
        }

        // Stop movie file recording (triggers save to Photos)
        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            if self.multiCamSession != nil {
                self.frontMovieOutput?.stopRecording()
                self.backMovieOutput?.stopRecording()
                self.multiCamSession?.stopRunning()
            } else {
                self.movieFileOutput?.stopRecording()
                self.singleCamSession?.stopRunning()
            }
        }

        // Stop location
        locationService.stopTracking()

        // Update UI
        await MainActor.run {
            self.isRecording = false
        }
    }

    // MARK: - Camera Switching (only for single camera mode)

    func flipCamera() {
        guard let session = singleCamSession else { return }

        let newPosition: AVCaptureDevice.Position = (currentCameraPosition == .front) ? .back : .front

        guard let newCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition) else {
            debugLog("[OnTheRecord] Could not get camera for position: \(newPosition)")
            return
        }
        
        // ... (Configuration omitted)
        
        sessionQueue.async { [weak self] in
            session.beginConfiguration()
            
            if let currentInput = session.inputs.first(where: { input in
                guard let deviceInput = input as? AVCaptureDeviceInput else { return false }
                return deviceInput.device.hasMediaType(.video)
            }) {
                session.removeInput(currentInput)
            }

            do {
                let newInput = try AVCaptureDeviceInput(device: newCamera)
                if session.canAddInput(newInput) {
                    session.addInput(newInput)
                }
            } catch {
                debugLog("[OnTheRecord] Failed to add new camera input: \(error)")
            }

            session.commitConfiguration()

            DispatchQueue.main.async {
                self?.currentCameraPosition = newPosition
            }
        }
    }

    // MARK: - Chunk Management (NAS Backup)

    @MainActor
    private func startChunkTimer() {
        chunkTimer = Timer.scheduledTimer(withTimeInterval: chunkDuration, repeats: true) { [weak self] _ in
            self?.rotateChunk()
        }
    }

    private func rotateChunk() {
        guard let writer = chunkWriter else { return }

        Task {
            if let chunkURL = await writer.finalizeCurrentChunk() {
                await self.uploadChunk(chunkURL)
            }
            
            writer.startNewChunk()
            
            await MainActor.run {
                self.currentChunkNumber += 1
            }
        }
    }

    private func uploadChunk(_ chunkURL: URL) async {
        let location = locationService.currentLocation
        let chunkNum = await MainActor.run { self.currentChunkNumber }

        let metadata = ChunkMetadata(
            incidentID: currentIncidentID ?? "",
            chunkNumber: chunkNum,
            timestamp: Date(),
            location: location,
            quality: currentQuality,
            deviceState: DeviceState.current()
        )
        
        do {
            // 1. Send to Live Stream (if active) - Use File URL (Zero RAM)
            if let liveStream = liveStreamService {
                await MainActor.run {
                    if liveStream.isStreaming {
                        liveStream.queueSegment(from: chunkURL, duration: chunkDuration)
                    }
                }
            }
            
            // 2. Load Data ONLY for Encryption (Ephemeral)
            let chunkData = try Data(contentsOf: chunkURL)
            
            // 3. Encrypt and Serialize
            if let encryptedChunk = try? encryptionService.encryptChunk(chunkData, metadata: metadata) {
                let serializedData = encryptedChunk.serialize()
                
                // 4. Write .iwc file (ready for upload)
                let iwcURL = chunkURL.deletingPathExtension().appendingPathExtension("iwc")
                try serializedData.write(to: iwcURL)
                
                // 4. Calculate integrity hash
                let hash = SHA256.hash(data: serializedData).compactMap { String(format: "%02x", $0) }.joined()
                
                // 5. Queue for persistent background upload
                await uploadService?.queueChunk(fileURL: iwcURL, incidentID: currentIncidentID ?? "", chunkNumber: chunkNum, hash: hash)
                
                // 6. Delete intermediate MP4
                try FileManager.default.removeItem(at: chunkURL)
            }
            
        } catch {
            debugLog("[RecordingService] Error processing chunk: \(error)")
        }
    }

    // MARK: - Save to Photos

    private func saveVideoToPhotos(url: URL, isFront: Bool) {
        let saveToVaultOnly = UserDefaults.standard.bool(forKey: "save_to_vault")
        
        // ALWAYS create a hidden vault backup (production hardening)
        // This ensures evidence survives even if Photos are deleted
        Task {
            _ = await createVaultBackup(from: url, isFront: isFront)
        }
        
        if saveToVaultOnly {
            // User only wants vault storage - just update status and clean up
            Task {
                await updateSaveStatus(success: true, isFront: isFront, scheme: "Vault")
                try? FileManager.default.removeItem(at: url)
            }
        } else {
            // Save to Photos (Default) - vault backup already created above
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            } completionHandler: { [weak self] success, error in
                Task {
                    await self?.updateSaveStatus(success: success, isFront: isFront, scheme: "Photos")
                    if success {
                        try? FileManager.default.removeItem(at: url)
                    } else {
                        debugLog("[OnTheRecord] Failed to save to Photos: \(error?.localizedDescription ?? "unknown")")
                    }
                }
            }
        }
    }
    
    /// Creates a hidden encrypted backup in the app's vault
    /// This is separate from Photos and invisible to casual inspection
    private func createVaultBackup(from url: URL, isFront: Bool) async -> Bool {
        // Copy file to temp location first (don't move the original, Photos needs it)
        let tempCopy = FileManager.default.temporaryDirectory
            .appendingPathComponent("vault_backup_\(UUID().uuidString).mov")
        
        do {
            try FileManager.default.copyItem(at: url, to: tempCopy)
            let success = VaultManager.shared.moveFileToVault(from: tempCopy)
            if success {
                debugLog("[OnTheRecord] Hidden vault backup created for \(isFront ? "front" : "back") camera")
            }
            return success
        } catch {
            debugLog("[OnTheRecord] Failed to create vault backup: \(error)")
            return false
        }
    }
    
    @MainActor
    private func updateSaveStatus(success: Bool, isFront: Bool, scheme: String) {
        if isFront {
            self.frontSavedToPhotos = success
        } else {
            self.backSavedToPhotos = success
        }

        // Update overall status
        if self.multiCamSession != nil {
            // Dual camera mode
            self.savedToPhotos = (self.frontSavedToPhotos ) && (self.backSavedToPhotos )
        } else {
            // Single camera mode
            self.savedToPhotos = success
        }

        if success {
            debugLog("[OnTheRecord] Video saved to \(scheme) (front: \(isFront))")
        }
    }
    
    // MARK: - Thermal Throttling
    
    private func startThermalMonitoring() {
        thermalStateObservation = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.adjustQualityForThermalState()
        }
    }
    
    @MainActor
    private func adjustQualityForThermalState() {
        let state = ProcessInfo.processInfo.thermalState
        var newQuality = self.currentQuality
        
        switch state {
        case .nominal:
            // Cool - maintain or upgrade to high quality
            if currentQuality != .high {
                debugLog("[OnTheRecord] Thermal state NOMINAL. Restoring high quality.")
                newQuality = .high
            }
        case .fair:
            // Getting warm - optional step down if we wanted to be proactive
            // For now, allow high quality if we were already there, or upgrade from low if we cooled down
             if currentQuality == .low {
                debugLog("[OnTheRecord] Thermal state FAIR. Restoring medium quality.")
                newQuality = .medium
            }
        case .serious:
            // Hot - downgrade to medium (720p)
            debugLog("[OnTheRecord] Thermal state SERIOUS. Downgrading to medium quality.")
            newQuality = .medium
        case .critical:
            // Very hot - downgrade to low (480p) to keep camera alive
            debugLog("[OnTheRecord] Thermal state CRITICAL. Downgrading to low quality.")
            newQuality = .low
        @unknown default:
            break
        }
        
        // If quality needs to change and we are recording, logic to restart/adjust writer would go here.
        // For MVP, we at least update the currentQuality so NEXT chunk uses it.
        // A more advanced impl would restart the session if hardware is struggling.
        if newQuality != self.currentQuality {
            self.currentQuality = newQuality
            
            // If running, tell writer to use new quality for next chunk
            if isRecording, let writer = chunkWriter {
                writer.updateQuality(newQuality) 
            }
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension RecordingService: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let writer = chunkWriter else { return }

        if output is AVCaptureVideoDataOutput {
            writer.appendVideoSample(sampleBuffer)
        } else if output is AVCaptureAudioDataOutput {
            writer.appendAudioSample(sampleBuffer)
        }
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate

extension RecordingService: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let error = error {
            debugLog("[OnTheRecord] Recording error: \(error.localizedDescription)")
            return
        }

        // Determine which camera this is from
        let isFront = (output == frontMovieOutput) ||
                      (movieFileOutput != nil && currentCameraPosition == .front)

        // Save the recorded video to Photos library
        saveVideoToPhotos(url: outputFileURL, isFront: isFront)
    }
}
