import SwiftUI
import AVFoundation

// MARK: - Single Camera Preview (Fallback for non-MultiCam devices)

struct CameraPreviewView: UIViewRepresentable {
    @ObservedObject var recordingService: RecordingService

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let layer = recordingService.previewLayer else { return }
        if layer.superlayer !== uiView.layer {
            uiView.layer.sublayers?.forEach { $0.removeFromSuperlayer() }
            layer.videoGravity = .resizeAspectFill
            uiView.layer.addSublayer(layer)
        }
        layer.frame = uiView.bounds
    }
}
