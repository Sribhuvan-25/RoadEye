import SwiftUI

struct ContentView: View {
    @StateObject private var controller: CameraFPSController
    @StateObject private var location: LocationRecorder
    @StateObject private var recorder: SessionRecorder

    init() {
        let cam = CameraFPSController()
        let loc = LocationRecorder()
        _controller = StateObject(wrappedValue: cam)
        _location = StateObject(wrappedValue: loc)
        _recorder = StateObject(wrappedValue: SessionRecorder(camera: cam, location: loc))
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                CameraPreviewView(session: controller.session)
                    .ignoresSafeArea()

                statusBar

                VStack {
                    Spacer()
                    if recorder.processing {
                        Label("Processing session…", systemImage: "gearshape.2")
                            .padding(10)
                            .background(.black.opacity(0.6), in: Capsule())
                            .foregroundStyle(.white)
                    }
                    controls
                }
            }
            .onAppear { controller.start() }
            .onDisappear { controller.stop() }
        }
    }

    private var statusBar: some View {
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
            Spacer()
            NavigationLink(destination: SessionsView()) {
                Image(systemName: "list.bullet.rectangle").foregroundStyle(.white)
            }
        }
        .font(.subheadline.bold())
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.6))
    }

    private var controls: some View {
        Button {
            recorder.isRecording ? recorder.stop() : recorder.start()
        } label: {
            Image(systemName: recorder.isRecording ? "stop.circle.fill" : "record.circle")
                .font(.system(size: 68))
                .foregroundStyle(recorder.isRecording ? .red : .white)
        }
        .disabled(recorder.processing)
        .padding(.bottom, 40)
    }

    private func timeString(_ t: TimeInterval) -> String {
        String(format: "%02d:%02d", Int(t) / 60, Int(t) % 60)
    }
}
