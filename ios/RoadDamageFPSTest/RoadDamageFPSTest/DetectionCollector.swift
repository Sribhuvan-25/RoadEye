import CoreGraphics
import Foundation
import UIKit

/// Accumulates tracked detections during a recording session and keeps the
/// best (highest-confidence) cropped image per track, so a session can be
/// turned into DefectRecords + crops when recording stops. Fed by
/// CameraFPSController on the video queue; guard with its own serial queue.
final class DetectionCollector {
    private var detections: [FrameDetection] = []
    private var bestConfByTrack: [Int: Double] = [:]
    private var bestCropByTrack: [Int: UIImage] = [:]
    private let tracker = SimpleTracker()
    private let queue = DispatchQueue(label: "detection.collector")
    private(set) var active = false
    /// Full-frame pixel size the boxes are in -- needed for IPM measurement.
    private(set) var frameSize: CGSize = .zero

    func start() {
        queue.sync {
            detections = []
            bestConfByTrack = [:]
            bestCropByTrack = [:]
            tracker.reset()
            active = true
        }
    }

    func stop() { queue.sync { active = false } }

    /// Record one frame's detections. `frame` is the full frame image used to
    /// cut crops; boxes are in that image's pixel space.
    func add(
        timestamp: TimeInterval,
        classes: [String],
        confidences: [Double],
        boxes: [CGRect],
        frame: UIImage?
    ) {
        queue.async {
            guard self.active else { return }
            if let frame = frame, self.frameSize == .zero { self.frameSize = frame.size }
            let ids = self.tracker.update(boxes: boxes)
            for i in 0..<boxes.count {
                let id = ids[i]
                self.detections.append(FrameDetection(
                    timestamp: timestamp, trackID: id,
                    className: classes[i], confidence: confidences[i], bbox: boxes[i]
                ))
                if confidences[i] > (self.bestConfByTrack[id] ?? -1) {
                    self.bestConfByTrack[id] = confidences[i]
                    if let frame = frame, let crop = self.crop(frame, boxes[i]) {
                        self.bestCropByTrack[id] = crop
                    }
                }
            }
        }
    }

    func snapshot() -> (detections: [FrameDetection], crops: [Int: UIImage], frameSize: CGSize) {
        queue.sync { (detections, bestCropByTrack, frameSize) }
    }

    private func crop(_ image: UIImage, _ box: CGRect) -> UIImage? {
        guard let cg = image.cgImage else { return nil }
        let pad: CGFloat = 0.15
        let r = box.insetBy(dx: -box.width * pad, dy: -box.height * pad)
            .intersection(CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        guard let c = cg.cropping(to: r) else { return nil }
        return UIImage(cgImage: c)
    }
}
