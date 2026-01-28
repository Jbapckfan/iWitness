import SwiftUI
import AVFoundation

// MARK: - Single Camera Preview

struct CameraPreviewView: UIViewRepresentable {
    @ObservedObject var recordingService: RecordingService
    
    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.backgroundColor = .black
        return view
    }
    
    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        if let session = recordingService.captureSession {
            uiView.setSession(session)
        }
    }
}

// MARK: - Dual Camera Preview (PiP style)

struct DualCameraPreviewView: UIViewRepresentable {
    @ObservedObject var recordingService: RecordingService
    
    func makeUIView(context: Context) -> DualPreviewUIView {
        let view = DualPreviewUIView()
        view.backgroundColor = .black
        return view
    }
    
    func updateUIView(_ uiView: DualPreviewUIView, context: Context) {
        if let backSession = recordingService.captureSession {
            uiView.setBackSession(backSession)
        }
        if let frontSession = recordingService.frontCaptureSession {
            uiView.setFrontSession(frontSession)
        }
    }
}

// MARK: - UIKit Preview View (Single)

class PreviewUIView: UIView {
    private var previewLayer: AVCaptureVideoPreviewLayer?
    
    override class var layerClass: AnyClass {
        return AVCaptureVideoPreviewLayer.self
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupPreviewLayer()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupPreviewLayer()
    }
    
    private func setupPreviewLayer() {
        guard let layer = self.layer as? AVCaptureVideoPreviewLayer else { return }
        layer.videoGravity = .resizeAspectFill
        previewLayer = layer
    }
    
    func setSession(_ session: AVCaptureSession) {
        guard let layer = self.layer as? AVCaptureVideoPreviewLayer else { return }
        layer.session = session
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }
}

// MARK: - UIKit Preview View (Dual - PiP)

class DualPreviewUIView: UIView {
    private var backPreviewLayer: AVCaptureVideoPreviewLayer?
    private var frontPreviewLayer: AVCaptureVideoPreviewLayer?
    private var frontPreviewContainer: UIView?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayers()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayers()
    }
    
    private func setupLayers() {
        // Main (back camera) layer
        let backLayer = AVCaptureVideoPreviewLayer()
        backLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(backLayer)
        backPreviewLayer = backLayer
        
        // PiP container for front camera
        let pipContainer = UIView()
        pipContainer.backgroundColor = .black
        pipContainer.layer.cornerRadius = 12
        pipContainer.layer.masksToBounds = true
        pipContainer.layer.borderColor = UIColor.white.withAlphaComponent(0.3).cgColor
        pipContainer.layer.borderWidth = 2
        addSubview(pipContainer)
        frontPreviewContainer = pipContainer
        
        // Front camera layer (inside PiP)
        let frontLayer = AVCaptureVideoPreviewLayer()
        frontLayer.videoGravity = .resizeAspectFill
        pipContainer.layer.addSublayer(frontLayer)
        frontPreviewLayer = frontLayer
    }
    
    func setBackSession(_ session: AVCaptureSession) {
        backPreviewLayer?.session = session
    }
    
    func setFrontSession(_ session: AVCaptureSession) {
        frontPreviewLayer?.session = session
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        // Back camera fills entire view
        backPreviewLayer?.frame = bounds
        
        // Front camera PiP in bottom-right corner
        let pipSize: CGFloat = min(bounds.width, bounds.height) * 0.3
        let padding: CGFloat = 20
        let safeAreaBottom = safeAreaInsets.bottom
        
        frontPreviewContainer?.frame = CGRect(
            x: bounds.width - pipSize - padding,
            y: bounds.height - pipSize - padding - safeAreaBottom - 100, // Above controls
            width: pipSize,
            height: pipSize * 1.3 // Taller for portrait aspect
        )
        
        frontPreviewLayer?.frame = frontPreviewContainer?.bounds ?? .zero
    }
}
