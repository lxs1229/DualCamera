import AVFoundation
import CoreImage
import UIKit

final class CameraManager: NSObject, ObservableObject {
    enum CameraError: Error {
        case multiCamUnsupported
        case configurationFailed
        case missingInputs
    }

    @Published var latestComposite: UIImage?
    @Published var isRunning = false
    @Published var errorMessage: String?

    let session = AVCaptureMultiCamSession()

    private let backPhotoOutput = AVCapturePhotoOutput()
    private let frontPhotoOutput = AVCapturePhotoOutput()
    private var backPhotoData: Data?
    private var frontPhotoData: Data?

    private var backPreviewLayer: AVCaptureVideoPreviewLayer?
    private var frontPreviewLayer: AVCaptureVideoPreviewLayer?

    func configureSession() {
        guard AVCaptureMultiCamSession.isMultiCamSupported else {
            errorMessage = "此设备不支持多摄像头拍摄。"
            return
        }

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .photo

        do {
            try addInputs()
            try addOutputs()
            try addPreviewLayers()
        } catch {
            errorMessage = "配置摄像头失败：\(error.localizedDescription)"
        }
    }

    private func addInputs() throws {
        session.inputs.forEach { session.removeInput($0) }

        guard
            let backDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let frontDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        else {
            throw CameraError.missingInputs
        }

        let backInput = try AVCaptureDeviceInput(device: backDevice)
        let frontInput = try AVCaptureDeviceInput(device: frontDevice)

        guard session.canAddInput(backInput), session.canAddInput(frontInput) else {
            throw CameraError.configurationFailed
        }

        session.addInputWithNoConnections(backInput)
        session.addInputWithNoConnections(frontInput)
    }

    private func addOutputs() throws {
        session.outputs.forEach { session.removeOutput($0) }

        guard session.canAddOutput(backPhotoOutput), session.canAddOutput(frontPhotoOutput) else {
            throw CameraError.configurationFailed
        }

        backPhotoOutput.isHighResolutionCaptureEnabled = true
        frontPhotoOutput.isHighResolutionCaptureEnabled = true

        session.addOutputWithNoConnections(backPhotoOutput)
        session.addOutputWithNoConnections(frontPhotoOutput)

        guard
            let backInput = session.inputs.compactMap({ $0 as? AVCaptureDeviceInput }).first(where: { $0.device.position == .back }),
            let frontInput = session.inputs.compactMap({ $0 as? AVCaptureDeviceInput }).first(where: { $0.device.position == .front })
        else {
            throw CameraError.missingInputs
        }

        let backPort = backInput.ports.first(where: { $0.mediaType == .video })
        let frontPort = frontInput.ports.first(where: { $0.mediaType == .video })

        guard let backPort, let frontPort else {
            throw CameraError.configurationFailed
        }

        let backConnection = AVCaptureConnection(inputPorts: [backPort], output: backPhotoOutput)
        let frontConnection = AVCaptureConnection(inputPorts: [frontPort], output: frontPhotoOutput)

        guard session.canAddConnection(backConnection), session.canAddConnection(frontConnection) else {
            throw CameraError.configurationFailed
        }

        session.addConnection(backConnection)
        session.addConnection(frontConnection)
    }

    private func addPreviewLayers() throws {
        backPreviewLayer = AVCaptureVideoPreviewLayer(sessionWithNoConnection: session)
        frontPreviewLayer = AVCaptureVideoPreviewLayer(sessionWithNoConnection: session)

        guard
            let backPreviewLayer,
            let frontPreviewLayer,
            let backInput = session.inputs.compactMap({ $0 as? AVCaptureDeviceInput }).first(where: { $0.device.position == .back }),
            let frontInput = session.inputs.compactMap({ $0 as? AVCaptureDeviceInput }).first(where: { $0.device.position == .front })
        else {
            throw CameraError.configurationFailed
        }

        let backPort = backInput.ports.first(where: { $0.mediaType == .video })
        let frontPort = frontInput.ports.first(where: { $0.mediaType == .video })

        guard let backPort, let frontPort else {
            throw CameraError.configurationFailed
        }

        let backConnection = AVCaptureConnection(inputPort: backPort, videoPreviewLayer: backPreviewLayer)
        let frontConnection = AVCaptureConnection(inputPort: frontPort, videoPreviewLayer: frontPreviewLayer)

        guard session.canAddConnection(backConnection), session.canAddConnection(frontConnection) else {
            throw CameraError.configurationFailed
        }

        session.addConnection(backConnection)
        session.addConnection(frontConnection)
    }

    func makePreviewLayers() -> (AVCaptureVideoPreviewLayer?, AVCaptureVideoPreviewLayer?) {
        (backPreviewLayer, frontPreviewLayer)
    }

    func startSession() {
        guard !session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            self.session.startRunning()
            DispatchQueue.main.async {
                self.isRunning = true
            }
        }
    }

    func stopSession() {
        guard session.isRunning else { return }
        session.stopRunning()
        isRunning = false
    }

    func captureComposite() {
        backPhotoData = nil
        frontPhotoData = nil

        let settings = AVCapturePhotoSettings()
        settings.flashMode = .off

        backPhotoOutput.capturePhoto(with: settings, delegate: self)
        frontPhotoOutput.capturePhoto(with: settings, delegate: self)
    }

    private func tryComposeImage() {
        guard
            let backData = backPhotoData,
            let frontData = frontPhotoData,
            let backImage = UIImage(data: backData),
            let frontImage = UIImage(data: frontData)
        else {
            return
        }

        let composite = composePictureInPicture(base: backImage, overlay: frontImage)
        latestComposite = composite
    }

    private func composePictureInPicture(base: UIImage, overlay: UIImage) -> UIImage? {
        let baseSize = base.size
        let overlayScale: CGFloat = 0.3
        let overlaySize = CGSize(width: baseSize.width * overlayScale, height: baseSize.height * overlayScale)
        let overlayOrigin = CGPoint(
            x: baseSize.width - overlaySize.width - 32,
            y: baseSize.height - overlaySize.height - 32
        )

        let renderer = UIGraphicsImageRenderer(size: baseSize)
        return renderer.image { context in
            base.draw(in: CGRect(origin: .zero, size: baseSize))
            overlay.draw(in: CGRect(origin: overlayOrigin, size: overlaySize))
            let borderRect = CGRect(origin: overlayOrigin, size: overlaySize)
            UIColor.white.setStroke()
            let path = UIBezierPath(roundedRect: borderRect, cornerRadius: 12)
            path.lineWidth = 6
            path.stroke()
        }
    }
}

extension CameraManager: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil else {
            errorMessage = "拍摄失败：\(error?.localizedDescription ?? "未知错误")"
            return
        }

        guard let data = photo.fileDataRepresentation() else {
            errorMessage = "无法读取照片数据。"
            return
        }

        if output == backPhotoOutput {
            backPhotoData = data
        } else if output == frontPhotoOutput {
            frontPhotoData = data
        }

        tryComposeImage()
    }
}
