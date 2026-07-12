import SwiftUI

struct ContentView: View {
    @StateObject private var controller: CameraFPSController
    @StateObject private var location: LocationRecorder
    @StateObject private var recorder: SessionRecorder
    @State private var showShare = false

    init() {
        let cam = CameraFPSController()
        let loc = LocationRecorder()
        _controller = StateObject(wrappedValue: cam)
        _location = StateObject(wrappedValue: loc)
        _recorder = StateObject(wrappedValue: SessionRecorder(camera: cam, location: loc))
    }

    var body: some View {
        ZStack(alignment: .top) {
            CameraPreviewView(session: controller.session)
                .ignoresSafeArea()

            statusBar

            VStack {
                Spacer()
                controls
            }
        }
        .onAppear { controller.start() }
        .onDisappear { controller.stop() }
        .sheet(isPresented: $showShare) {
            if let url = recorder.lastSessionURL {
                ShareSheet(items: [url])
            }
        }
    }

    private var statusBar: some View {
        VStack(spacing: 4) {
            HStack(spacing: 12) {
                Label("\(controller.detectionCount)", systemImage: "scope")
                    .foregroundStyle(.yellow)
                Label(location.authorized ? "GPS" : "No GPS",
                      systemImage: location.authorized ? "location.fill" : "location.slash")
                    .foregroundStyle(location.authorized ? .green : .red)
                if recorder.isRecording {
                    Label(timeString(recorder.elapsed), systemImage: "record.circle")
                        .foregroundStyle(.red)
                }
            }
            .font(.subheadline.bold())
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.6))
    }

    private var controls: some View {
        HStack(spacing: 40) {
            Button {
                recorder.isRecording ? recorder.stop() : recorder.start()
            } label: {
                Image(systemName: recorder.isRecording ? "stop.circle.fill" : "record.circle")
                    .font(.system(size: 68))
                    .foregroundStyle(recorder.isRecording ? .red : .white)
            }

            if !recorder.isRecording && recorder.lastSessionURL != nil {
                Button { showShare = true } label: {
                    Image(systemName: "square.and.arrow.up.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(.bottom, 40)
    }

    private func timeString(_ t: TimeInterval) -> String {
        String(format: "%02d:%02d", Int(t) / 60, Int(t) % 60)
    }
}

/// Wraps UIActivityViewController so a finished session folder can be exported
/// via the iOS share sheet (AirDrop, Files, etc.).
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
