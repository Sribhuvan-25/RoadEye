import CoreGraphics
import Foundation

/// Minimal IoU tracker: assigns stable track IDs across frames by matching
/// each detection to the nearest recent track it overlaps. Vision's
/// VNCoreMLRequest returns per-frame detections with no identity across
/// frames (unlike Ultralytics' ByteTrack in the Python reference), so we
/// track here. Greedy IoU matching is enough for forward-driving footage
/// where defects move smoothly and rarely cross.
final class SimpleTracker {
    struct Track {
        let id: Int
        var bbox: CGRect
        var lastSeenFrame: Int
    }

    private var tracks: [Track] = []
    private var nextID = 1
    private var frameIndex = 0

    private let iouThreshold: CGFloat
    private let maxGapFrames: Int

    init(iouThreshold: CGFloat = 0.3, maxGapFrames: Int = 15) {
        self.iouThreshold = iouThreshold
        self.maxGapFrames = maxGapFrames
    }

    func update(boxes: [CGRect]) -> [Int] {
        frameIndex += 1
        tracks.removeAll { frameIndex - $0.lastSeenFrame > maxGapFrames }

        var assigned = [Int](repeating: -1, count: boxes.count)
        var usedTracks = Set<Int>()

        for (i, box) in boxes.enumerated() {
            var bestTrack = -1
            var bestIoU = iouThreshold
            for (ti, track) in tracks.enumerated() where !usedTracks.contains(ti) {
                let o = iou(box, track.bbox)
                if o >= bestIoU { bestIoU = o; bestTrack = ti }
            }
            if bestTrack >= 0 {
                tracks[bestTrack].bbox = box
                tracks[bestTrack].lastSeenFrame = frameIndex
                usedTracks.insert(bestTrack)
                assigned[i] = tracks[bestTrack].id
            } else {
                let t = Track(id: nextID, bbox: box, lastSeenFrame: frameIndex)
                tracks.append(t)
                usedTracks.insert(tracks.count - 1)
                assigned[i] = nextID
                nextID += 1
            }
        }
        return assigned
    }

    func reset() {
        tracks = []
        nextID = 1
        frameIndex = 0
    }

    private func iou(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let inter = a.intersection(b)
        if inter.isNull { return 0 }
        let interArea = inter.width * inter.height
        let union = a.width * a.height + b.width * b.height - interArea
        return union <= 0 ? 0 : interArea / union
    }
}
