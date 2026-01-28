import AVFoundation
import Photos
import SwiftUI

@MainActor
final class CameraManager: NSObject, ObservableObject {
    @Published var statusMessage: String?

    let session = AVCaptureMultiCamSession()
    let backPreviewLayer = AVCaptureVideoPreviewLayer()
    let frontPreviewLayer = AVCaptureVideoPreviewLayer()

    private let sessionQueue = DispatchQueue(label: "dual.camera.session")
    private let outputQueue = DispatchQueue(label: "dual.camera.output")
    private var backVideoOutput: AVCaptureVideoDataOutput?
    private var frontVideoOutput: AVCaptureVideoDataOutput?

    private var latestBackSampleBuffer: CMSampleBuffer?
    private var latestFrontSampleBuffer: CMSampleBuffer?

    var isMultiCamSupported: Bool {
        AVCaptureMultiCamSession.isMultiCamSupported
    }

    func configureSession() async {
        guard isMultiCamSupported else {
            statusMessage = "Dual camera capture is not supported on this device."
            return
        }

        let cameraAuth = AVCaptureDevice.authorizationStatus(for: .video)
        if cameraAuth == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if !granted {
                statusMessage = "Camera access is required."
                return
            }
        } else if cameraAuth != .authorized {
            statusMessage = "Camera access is required."
            return
        }

        await withCheckedContinuation { continuation in
            sessionQueue.async {
                self.configureSessionOnQueue()
                continuation.resume()
            }
        }
    }

    func stopSession() {
        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    func capturePhoto() {
        guard let backBuffer = latestBackSampleBuffer,
              let frontBuffer = latestFrontSampleBuffer else {
            statusMessage = "Still warming up the cameras."
            return
        }

        outputQueue.async {
            guard let backImage = self.uiImage(from: backBuffer),
                  let frontImage = self.uiImage(from: frontBuffer) else {
                Task { @MainActor in
                    self.statusMessage = "Unable to capture photo."
                }
                return
            }

            let composed = self.composePictureInPicture(background: backImage, overlay: frontImage)
            self.saveToPhotoLibrary(image: composed)
        }
    }

    private func configureSessionOnQueue() {
        session.beginConfiguration()
        session.sessionPreset = .high

        backPreviewLayer.session = session
        frontPreviewLayer.session = session

        guard let backCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let frontCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let backInput = try? AVCaptureDeviceInput(device: backCamera),
              let frontInput = try? AVCaptureDeviceInput(device: frontCamera) else {
            Task { @MainActor in
                self.statusMessage = "Unable to access cameras."
            }
            session.commitConfiguration()
            return
        }

        if session.canAddInput(backInput) {
            session.addInputWithNoConnections(backInput)
        }
        if session.canAddInput(frontInput) {
            session.addInputWithNoConnections(frontInput)
        }

        let backOutput = AVCaptureVideoDataOutput()
        backOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        backOutput.setSampleBufferDelegate(self, queue: outputQueue)

        let frontOutput = AVCaptureVideoDataOutput()
        frontOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        frontOutput.setSampleBufferDelegate(self, queue: outputQueue)

        if session.canAddOutput(backOutput) {
            session.addOutputWithNoConnections(backOutput)
        }
        if session.canAddOutput(frontOutput) {
            session.addOutputWithNoConnections(frontOutput)
        }

        if let backPort = backInput.ports.first(where: { $0.mediaType == .video }),
           let backPreviewConnection = AVCaptureConnection(inputPorts: [backPort], videoPreviewLayer: backPreviewLayer),
           session.canAddConnection(backPreviewConnection) {
            backPreviewConnection.videoOrientation = .portrait
            session.addConnection(backPreviewConnection)
        }

        if let frontPort = frontInput.ports.first(where: { $0.mediaType == .video }),
           let frontPreviewConnection = AVCaptureConnection(inputPorts: [frontPort], videoPreviewLayer: frontPreviewLayer),
           session.canAddConnection(frontPreviewConnection) {
            frontPreviewConnection.videoOrientation = .portrait
            frontPreviewConnection.isVideoMirrored = true
            session.addConnection(frontPreviewConnection)
        }

        if let backPort = backInput.ports.first(where: { $0.mediaType == .video }),
           let backOutputConnection = AVCaptureConnection(inputPorts: [backPort], output: backOutput),
           session.canAddConnection(backOutputConnection) {
            backOutputConnection.videoOrientation = .portrait
            session.addConnection(backOutputConnection)
        }

        if let frontPort = frontInput.ports.first(where: { $0.mediaType == .video }),
           let frontOutputConnection = AVCaptureConnection(inputPorts: [frontPort], output: frontOutput),
           session.canAddConnection(frontOutputConnection) {
            frontOutputConnection.videoOrientation = .portrait
            frontOutputConnection.isVideoMirrored = true
            session.addConnection(frontOutputConnection)
        }

        backVideoOutput = backOutput
        frontVideoOutput = frontOutput

        session.commitConfiguration()
        session.startRunning()
    }

    private func uiImage(from sampleBuffer: CMSampleBuffer) -> UIImage? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return nil
        }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    private func composePictureInPicture(background: UIImage, overlay: UIImage) -> UIImage {
        let baseSize = background.size
        let overlayScale: CGFloat = 0.3
        let overlaySize = CGSize(width: baseSize.width * overlayScale, height: baseSize.height * overlayScale)
        let padding: CGFloat = baseSize.width * 0.04
        let origin = CGPoint(x: baseSize.width - overlaySize.width - padding, y: padding)

        let renderer = UIGraphicsImageRenderer(size: baseSize)
        return renderer.image { context in
            background.draw(in: CGRect(origin: .zero, size: baseSize))

            let overlayRect = CGRect(origin: origin, size: overlaySize)
            let path = UIBezierPath(roundedRect: overlayRect, cornerRadius: overlaySize.width * 0.08)
            path.addClip()
            overlay.draw(in: overlayRect)

            UIColor.white.withAlphaComponent(0.8).setStroke()
            path.lineWidth = max(2, overlaySize.width * 0.01)
            path.stroke()
        }
    }

    private func saveToPhotoLibrary(image: UIImage) {
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized || status == .limited else {
                Task { @MainActor in
                    self.statusMessage = "Photo library permission denied."
                }
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: image.jpegData(compressionQuality: 0.92) ?? Data(), options: nil)
            }, completionHandler: { success, error in
                Task { @MainActor in
                    if success {
                        self.statusMessage = "Saved to Photos."
                    } else {
                        self.statusMessage = error?.localizedDescription ?? "Save failed."
                    }
                }
            })
        }
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if output === backVideoOutput {
            latestBackSampleBuffer = sampleBuffer
        } else if output === frontVideoOutput {
            latestFrontSampleBuffer = sampleBuffer
        }
    }
}
