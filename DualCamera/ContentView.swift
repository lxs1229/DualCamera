import SwiftUI

struct ContentView: View {
    @StateObject private var cameraManager = CameraManager()

    var body: some View {
        ZStack {
            if cameraManager.isMultiCamSupported {
                CameraPreviewView(previewLayer: cameraManager.backPreviewLayer)
                    .ignoresSafeArea()

                CameraPreviewView(previewLayer: cameraManager.frontPreviewLayer)
                    .frame(width: 160, height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.8), lineWidth: 2)
                    )
                    .shadow(radius: 6)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

                VStack {
                    Spacer()
                    Button(action: cameraManager.capturePhoto) {
                        Circle()
                            .strokeBorder(Color.white, lineWidth: 5)
                            .background(Circle().fill(Color.white.opacity(0.2)))
                            .frame(width: 76, height: 76)
                    }
                    .padding(.bottom, 24)
                }

                if let message = cameraManager.statusMessage {
                    Text(message)
                        .padding(12)
                        .background(.black.opacity(0.6))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .padding(.top, 16)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "video.slash")
                        .font(.system(size: 48))
                    Text("This device does not support dual camera capture.")
                        .multilineTextAlignment(.center)
                }
                .padding()
            }
        }
        .task {
            await cameraManager.configureSession()
        }
        .onDisappear {
            cameraManager.stopSession()
        }
    }
}

#Preview {
    ContentView()
}
