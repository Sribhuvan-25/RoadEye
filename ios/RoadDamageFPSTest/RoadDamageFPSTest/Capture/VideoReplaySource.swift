import AVFoundation
import CoreVideo
import Foundation

/// Feeds frames from a video file into the capture pipeline in place of the
/// camera, so the full detect -> track -> crop -> measure -> save path can be
/// exercised on the Simulator (which has no camera) and against a fixed clip
/// whose results are repeatable. Ships only for local testing: the app uses
/// the real camera whenever one is available.
final class VideoReplaySource {
    private let url: URL
    private let frameHandler: (CVPixelBuffer) -> Void
    private var reader: AVAssetReader?
    private var output: AVAssetReaderTrackOutput?
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "video.replay")

    /// Frames are pushed at this rate; the pipeline drops any it is too busy
    /// to handle, exactly as it does with live camera frames.
    private let targetFPS: Double

    init(url: URL, targetFPS: Double = 30, frameHandler: @escaping (CVPixelBuffer) -> Void) {
        self.url = url
        self.targetFPS = targetFPS
        self.frameHandler = frameHandler
    }

    /// Starts replay off the main thread and reports success via `completion`
    /// so the caller never blocks the UI waiting on asset loading.
    func start(completion: @escaping (Bool) -> Void) {
        queue.async { [weak self] in
            guard let self, self.prepareReader() else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            let t = DispatchSource.makeTimerSource(queue: self.queue)
            t.schedule(deadline: .now(), repeating: 1.0 / self.targetFPS)
            t.setEventHandler { [weak self] in self?.pushNextFrame() }
            self.timer = t
            t.resume()
            DispatchQueue.main.async { completion(true) }
        }
    }

    func stop() {
        timer?.cancel()
        timer = nil
        reader?.cancelReading()
        reader = nil
        output = nil
    }

    private func prepareReader() -> Bool {
        let asset = AVURLAsset(url: url)
        // Loaded synchronously on the replay queue: this is a local bundled
        // file, so there is no network stall to schedule around.
        guard let track = loadVideoTrack(from: asset),
              let r = try? AVAssetReader(asset: asset) else { return false }

        let o = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String:
                Int(kCVPixelFormatType_32BGRA)
        ])
        guard r.canAdd(o) else { return false }
        r.add(o)
        guard r.startReading() else { return false }
        reader = r
        output = o
        return true
    }

    /// Safe because prepareReader() only ever runs on `queue`, never on main.
    private func loadVideoTrack(from asset: AVURLAsset) -> AVAssetTrack? {
        var result: AVAssetTrack?
        let done = DispatchSemaphore(value: 0)
        Task {
            result = try? await asset.loadTracks(withMediaType: .video).first
            done.signal()
        }
        done.wait()
        return result
    }

    private func pushNextFrame() {
        guard let output else { return }
        if let sample = output.copyNextSampleBuffer(),
           let pixels = CMSampleBufferGetImageBuffer(sample) {
            frameHandler(pixels)
            return
        }
        // Clip finished -- loop so a short test video keeps the feed alive.
        reader?.cancelReading()
        if !prepareReader() { stop() }
    }
}
