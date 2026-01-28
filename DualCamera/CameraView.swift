import AVFoundation
import SwiftUI

struct CameraView: View {
    @StateObject private var manager = CameraManager()
    @State private var showComposite = false

    var body: some View {
        ZStack {
            CameraPreview(manager: manager)
                .ignoresSafeArea()

            VStack {
                if let errorMessage = manager.errorMessage {
                    Text(errorMessage)
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                }

                Spacer()

                HStack {
                    Button(action: {
                        manager.captureComposite()
                        showComposite = true
                    }) {
                        Image(systemName: "camera.circle.fill")
                            .resizable()
                            .frame(width: 72, height: 72)
                            .foregroundColor(.white)
                            .shadow(radius: 8)
                    }
                }
                .padding(.bottom, 32)
            }
        }
        .onAppear {
            manager.configureSession()
            manager.startSession()
        }
        .onDisappear {
            manager.stopSession()
        }
        .sheet(isPresented: $showComposite) {
            if let image = manager.latestComposite {
                VStack {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding()

                    Button("关闭") {
                        showComposite = false
                    }
                    .padding(.bottom, 24)
                }
            } else {
                ProgressView("正在合成照片...")
                    .padding()
            }
        }
    }
}

struct CameraPreview: UIViewRepresentable {
    @ObservedObject var manager: CameraManager

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black

        if manager.makePreviewLayers().0 == nil {
            manager.configureSession()
        }

        if let layers = manager.makePreviewLayers() as (AVCaptureVideoPreviewLayer?, AVCaptureVideoPreviewLayer?)? {
            let backLayer = layers.0
            let frontLayer = layers.1

            backLayer?.videoGravity = .resizeAspectFill
            frontLayer?.videoGravity = .resizeAspectFill

            if let backLayer {
                backLayer.frame = view.bounds
                view.layer.addSublayer(backLayer)
            }

            if let frontLayer {
                frontLayer.frame = CGRect(
                    x: view.bounds.width * 0.65,
                    y: view.bounds.height * 0.65,
                    width: view.bounds.width * 0.3,
                    height: view.bounds.height * 0.3
                )
                frontLayer.cornerRadius = 16
                frontLayer.masksToBounds = true
                view.layer.addSublayer(frontLayer)
            }
        }

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let sublayers = uiView.layer.sublayers else { return }

        if let backLayer = sublayers.first as? AVCaptureVideoPreviewLayer {
            backLayer.frame = uiView.bounds
        }

        if sublayers.count > 1, let frontLayer = sublayers.last as? AVCaptureVideoPreviewLayer {
            frontLayer.frame = CGRect(
                x: uiView.bounds.width * 0.65,
                y: uiView.bounds.height * 0.65,
                width: uiView.bounds.width * 0.3,
                height: uiView.bounds.height * 0.3
            )
        }
    }
}
