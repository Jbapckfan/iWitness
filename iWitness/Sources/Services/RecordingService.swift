import Foundation
import AVFoundation
import CoreLocation
import Combine
import Photos

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
    private let encryptionService = EncryptionService()
    private let locationService = LocationService()

    // MARK: - Session Management

    private var currentIncidentID: String?
    private var chunkTimer: Timer?
    private let sessionQueue = DispatchQueue(label: "com.iwitness.session", qos: .userInitiated)
    private let processingQueue = DispatchQueue(label: "com.iwitness.processing", qos: .userInitiated)

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

    // MARK: - Initialization

    override init() {
        super.init()
        checkMultiCamSupport()
    }

    func configure(uploadService: UploadService) {
        self.uploadService = uploadService
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

            // Connect audio to both outputs
            if let audioPort = audioInput.ports(for: .audio, sourceDeviceType: nil, sourceDevicePosition: .unspecified).first {
                // Audio will be connected to movie outputs below
            }
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

        // Start location tracking
        locationService.startTracking()

        // Create local video file URLs
        let tempDir = FileManager.default.temporaryDirectory

        if useDualCamera {
            frontVideoURL = tempDir.appendingPathComponent("iWitness_\(incidentID)_front.mov")
            backVideoURL = tempDir.appendingPathComponent("iWitness_\(incidentID)_back.mov")
        } else {
            localVideoURL = tempDir.appendingPathComponent("iWitness_\(incidentID).mov")
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
        if let writer = chunkWriter, let chunkData = writer.finalizeCurrentChunk() {
            await uploadChunk(chunkData)
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
            print("[iWitness] Could not get camera for position: \(newPosition)")
            return
        }

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
                print("[iWitness] Failed to add new camera input: \(error)")
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

        if let chunkData = writer.finalizeCurrentChunk() {
            Task {
                await self.uploadChunk(chunkData)
            }
        }

        writer.startNewChunk()

        Task { @MainActor in
            self.currentChunkNumber += 1
        }
    }

    private func uploadChunk(_ chunkData: Data) async {
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

        if let encryptedChunk = try? encryptionService.encryptChunk(chunkData, metadata: metadata) {
            await uploadService?.queueChunk(encryptedChunk)
        }
    }

    // MARK: - Save to Photos

    private func saveVideoToPhotos(url: URL, isFront: Bool) {
        PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        } completionHandler: { [weak self] success, error in
            Task { @MainActor in
                if isFront {
                    self?.frontSavedToPhotos = success
                } else {
                    self?.backSavedToPhotos = success
                }

                // Update overall status
                if self?.multiCamSession != nil {
                    // Dual camera mode - both need to be saved
                    self?.savedToPhotos = (self?.frontSavedToPhotos ?? false) && (self?.backSavedToPhotos ?? false)
                } else {
                    // Single camera mode
                    self?.savedToPhotos = success
                }

                if success {
                    print("[iWitness] Video saved to Photos (front: \(isFront))")
                } else {
                    print("[iWitness] Failed to save to Photos: \(error?.localizedDescription ?? "unknown")")
                }

                // Clean up temp file
                try? FileManager.default.removeItem(at: url)
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
            print("[iWitness] Recording error: \(error.localizedDescription)")
            return
        }

        // Determine which camera this is from
        let isFront = (output == frontMovieOutput) ||
                      (movieFileOutput != nil && currentCameraPosition == .front)

        // Save the recorded video to Photos library
        saveVideoToPhotos(url: outputFileURL, isFront: isFront)
    }
}
