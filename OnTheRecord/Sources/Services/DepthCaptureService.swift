import Foundation
import AVFoundation
import ARKit
import Combine

/// Captures LiDAR depth data alongside video for 3D scene reconstruction
/// Gracefully degrades on non-LiDAR devices (silently skips)
@MainActor
class DepthCaptureService: ObservableObject {
    static let shared = DepthCaptureService()

    // MARK: - Published State

    @Published var isCapturing: Bool = false
    @Published var isLiDARAvailable: Bool = false
    @Published var framesCaptured: Int = 0
    @Published var depthDataSize: Int64 = 0

    // MARK: - Private

    private var depthOutput: AVCaptureDepthDataOutput?
    private var depthFrames: [DepthFrame] = []
    private var captureStartTime: Date?
    private var incidentID: String?
    private let processingQueue = DispatchQueue(label: "com.ontherecord.depth", qos: .userInitiated)

    // MARK: - Types

    struct DepthFrame: Codable {
        let timestamp: TimeInterval  // seconds from capture start
        let width: Int
        let height: Int
        let depthDataPath: String    // relative path to binary depth file
    }

    struct DepthCaptureManifest: Codable {
        let incidentID: String
        let deviceModel: String
        let captureStart: Date
        let captureEnd: Date?
        let frameCount: Int
        let frames: [DepthFrame]
    }

    // MARK: - Initialization

    init() {
        checkLiDARAvailability()
    }

    private func checkLiDARAvailability() {
        isLiDARAvailable = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
    }

    // MARK: - Capture Control

    /// Configure depth output on an existing capture session (call during session setup)
    func configureDepthCapture(session: AVCaptureMultiCamSession, backCameraInput: AVCaptureDeviceInput) -> Bool {
        guard isLiDARAvailable else {
            debugLog("[DepthCapture] LiDAR not available on this device, skipping")
            return false
        }

        // Check if the back camera supports depth
        guard let depthDevice = AVCaptureDevice.default(.builtInLiDARDepthCamera, for: .video, position: .back) else {
            debugLog("[DepthCapture] LiDAR depth camera not available")
            return false
        }

        let output = AVCaptureDepthDataOutput()
        output.isFilteringEnabled = true
        output.setDelegate(self, callbackQueue: processingQueue)

        guard session.canAddOutput(output) else {
            debugLog("[DepthCapture] Cannot add depth output to session")
            return false
        }

        session.addOutput(output)
        self.depthOutput = output

        debugLog("[DepthCapture] LiDAR depth capture configured")
        return true
    }

    func startCapture(incidentID: String) {
        self.incidentID = incidentID
        self.captureStartTime = Date()
        self.depthFrames = []
        self.framesCaptured = 0
        self.depthDataSize = 0
        self.isCapturing = true

        // Create depth data directory
        let dir = depthDirectory(for: incidentID)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        debugLog("[DepthCapture] Started capture for incident \(incidentID)")
    }

    func stopCapture() async {
        isCapturing = false

        // Save manifest
        guard let id = incidentID else { return }

        let manifest = DepthCaptureManifest(
            incidentID: id,
            deviceModel: UIDevice.current.model,
            captureStart: captureStartTime ?? Date(),
            captureEnd: Date(),
            frameCount: depthFrames.count,
            frames: depthFrames
        )

        let manifestURL = depthDirectory(for: id).appendingPathComponent("manifest.json")
        if let data = try? JSONEncoder().encode(manifest) {
            try? data.write(to: manifestURL)
        }

        debugLog("[DepthCapture] Stopped. Captured \(framesCaptured) depth frames, \(ByteCountFormatter.string(fromByteCount: depthDataSize, countStyle: .file))")
    }

    // MARK: - Export

    /// Export depth data as USDZ for AR viewing (requires RealityKit scene reconstruction)
    func exportAsUSDZ(incidentID: String) async throws -> URL? {
        // USDZ export would use ModelEntity from RealityKit
        // For now, export the raw depth data package
        let dir = depthDirectory(for: incidentID)
        guard FileManager.default.fileExists(atPath: dir.path) else { return nil }

        // The depth data directory itself is the export
        return dir
    }

    // MARK: - Helpers

    private func depthDirectory(for incidentID: String) -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("OnTheRecord", isDirectory: true)
            .appendingPathComponent("DepthData", isDirectory: true)
            .appendingPathComponent(incidentID, isDirectory: true)
    }
}

// MARK: - AVCaptureDepthDataOutputDelegate

extension DepthCaptureService: AVCaptureDepthDataOutputDelegate {
    nonisolated func depthDataOutput(_ output: AVCaptureDepthDataOutput, didOutput depthData: AVDepthData, timestamp: CMTime, connection: AVCaptureConnection) {
        // Sample at 2 FPS (every 15 frames at 30fps) to conserve storage
        let frameNumber = Task { @MainActor in self.framesCaptured }

        Task { @MainActor in
            guard isCapturing, let incidentID = self.incidentID, let startTime = captureStartTime else { return }

            // Only capture every 15th frame (~2fps depth data)
            guard framesCaptured % 15 == 0 else {
                framesCaptured += 1
                return
            }

            let elapsed = Date().timeIntervalSince(startTime)
            let depthMap = depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
            let pixelBuffer = depthMap.depthDataMap

            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)

            // Save depth data as binary float array
            let filename = String(format: "depth_%06d.bin", framesCaptured)
            let fileURL = depthDirectory(for: incidentID).appendingPathComponent(filename)

            CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
            if let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) {
                let dataSize = CVPixelBufferGetDataSize(pixelBuffer)
                let data = Data(bytes: baseAddress, count: dataSize)
                try? data.write(to: fileURL)
                depthDataSize += Int64(dataSize)
            }
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)

            let frame = DepthFrame(
                timestamp: elapsed,
                width: width,
                height: height,
                depthDataPath: filename
            )
            depthFrames.append(frame)
            framesCaptured += 1
        }
    }
}
