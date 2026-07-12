import AVFoundation
import Combine
import UIKit

/// Records a drive session: starts video capture and GPS logging on a shared
/// clock, and on stop writes both into one session folder (video.mov +
/// gps.csv) in Documents, ready to export to the Python backend.
///
/// Video and GPS share a session-start timestamp (CACurrentMediaTime) so the
/// GPS log's t_s column lines up with the video's frame times -- the backend
/// interpolates locations onto detections using exactly that alignment.
final class SessionRecorder: NSObject, ObservableObject, AVCaptureFileOutputRecordingDelegate {
    @Published var isRecording = false
    @Published var elapsed: TimeInterval = 0
    @Published var lastSessionURL: URL?

    private let camera: CameraFPSController
    private let location: LocationRecorder
    private var sessionDir: URL?
    private var startTime: CFTimeInterval = 0
    private var timer: Timer?

    init(camera: CameraFPSController, location: LocationRecorder) {
        self.camera = camera
        self.location = location
    }

    func start() {
        guard !isRecording else { return }
        let stamp = Int(Date().timeIntervalSince1970)
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("session_\(stamp)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        sessionDir = dir

        startTime = CACurrentMediaTime()
        location.startSession(at: startTime)
        camera.movieOutput.startRecording(to: dir.appendingPathComponent("video.mov"), recordingDelegate: self)

        isRecording = true
        elapsed = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, self.isRecording else { return }
            self.elapsed = CACurrentMediaTime() - self.startTime
        }
    }

    func stop() {
        guard isRecording else { return }
        camera.movieOutput.stopRecording()   // finalizes video in the delegate callback
        location.stopSession()
        timer?.invalidate()
        isRecording = false

        if let dir = sessionDir {
            try? location.csv().write(to: dir.appendingPathComponent("gps.csv"),
                                      atomically: true, encoding: .utf8)
            lastSessionURL = dir
        }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection], error: Error?) {
        // video file is finalized here; nothing extra needed for the MVP
    }
}
