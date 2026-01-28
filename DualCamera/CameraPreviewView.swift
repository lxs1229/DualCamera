import AVFoundation
import SwiftUI

struct CameraPreviewView: UIViewRepresentable {
    let previewLayer: AVCaptureVideoPreviewLayer?

    func makeUIView(context: Context) -> PreviewView {
        PreviewView()
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.videoPreviewLayer.session = previewLayer?.session
        if let connection = previewLayer?.connection {
            uiView.videoPreviewLayer.connection?.videoOrientation = connection.videoOrientation
            uiView.videoPreviewLayer.connection?.automaticallyAdjustsVideoMirroring = false
            uiView.videoPreviewLayer.connection?.isVideoMirrored = connection.isVideoMirrored
        }
    }
}

final class PreviewView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        videoPreviewLayer.videoGravity = .resizeAspectFill
    }
}
