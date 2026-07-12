import AVFoundation
import Combine
import UIKit

/// Records a drive and, on stop, runs the full on-device pipeline
/// (track -> dedup -> geotag -> measure) to save a browsable session archive:
/// defect crops + defects.json in Documents/sessions/<id>/. The video and GPS
/// share a session-start clock so locations interpolate onto detections.
///
/// Camera geometry (mount height, horizon row) drives the IPM measurement;
/// defaults are reasonable for a windshield mount and can be tuned in Settings.
final class SessionRecorder: NSObject, ObservableObject, AVCaptureFileOutputRecordingDelegate {
    @Published var isRecording = false
    @Published var elapsed: TimeInterval = 0
    @Published var lastSessionID: String?
    @Published var processing = false

    /// Per-vehicle mount config for measurement.
    var mountHeightM: Double = 1.3
    var horizonFraction: Double = 0.45   // horizon row as a fraction of frame height

    private let camera: CameraFPSController
    private let location: LocationRecorder
    private let collector = DetectionCollector()
    private var sessionID: String?
    private var sessionDir: URL?
    private var startTime: CFTimeInterval = 0
    private var startEpoch: Double = 0
    private var timer: Timer?

    init(camera: CameraFPSController, location: LocationRecorder) {
        self.camera = camera
        self.location = location
    }

    func start() {
        guard !isRecording else { return }
        let id = "session_\(Int(Date().timeIntervalSince1970))"
        sessionID = id
        let dir = SessionStore.sessionDir(id)
        sessionDir = dir

        startTime = CACurrentMediaTime()
        startEpoch = Date().timeIntervalSince1970
        location.startSession(at: startTime)
        collector.start()
        camera.collector = collector
        camera.movieOutput.startRecording(to: dir.appendingPathComponent("video.mov"),
                                          recordingDelegate: self)

        isRecording = true
        elapsed = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, self.isRecording else { return }
            self.elapsed = CACurrentMediaTime() - self.startTime
        }
    }

    func stop() {
        guard isRecording, let id = sessionID, let dir = sessionDir else { return }
        camera.movieOutput.stopRecording()
        location.stopSession()
        collector.stop()
        camera.collector = nil
        timer?.invalidate()
        isRecording = false
        let duration = CACurrentMediaTime() - startTime

        try? location.csv().write(to: dir.appendingPathComponent("gps.csv"),
                                  atomically: true, encoding: .utf8)

        processing = true
        let snap = collector.snapshot()
        let fixes = location.fixes()
        let height = mountHeightM
        let horizonFrac = horizonFraction
        let epoch = startEpoch

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let fs = snap.frameSize
            var camModel: CameraModel?
            if fs != .zero {
                camModel = Geometry.makeCamera(
                    imageWidth: Int(fs.width), imageHeight: Int(fs.height),
                    heightM: height, horizonRow: Double(fs.height) * horizonFrac)
            }
            let records = SessionProcessor.buildRecords(
                detections: snap.detections, gps: fixes, camera: camModel)
            SessionStore.save(id: id, startedEpoch: epoch, durationS: duration,
                              records: records, crops: snap.crops)
            DispatchQueue.main.async {
                self?.processing = false
                self?.lastSessionID = id
            }
        }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection], error: Error?) {}
}
