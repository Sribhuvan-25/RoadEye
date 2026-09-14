import CoreGraphics
import CoreLocation
import Foundation

/// Collapses live per-frame detections into one DefectRecord per physical
/// defect, geotags and measures each. Swift port of the grouping in
/// pipeline/track_and_dedup.py plus the GPS interpolation in pipeline/geo.py.
///
/// A defect seen across many frames shares a track ID (from the detector's
/// tracker); we keep the highest-confidence frame as its representative,
/// majority-vote its class, drop single-frame flickers, then attach the GPS
/// fix at its first-seen time and the IPM dimensions of its best bbox.
enum SessionProcessor {

    struct GpsFix {
        let t: TimeInterval
        let lat: Double
        let lon: Double
        let heading: Double?
    }

    static func buildRecords(
        detections: [FrameDetection],
        gps: [GpsFix],
        camera: CameraModel?,
        minTrackLen: Int = 2
    ) -> [DefectRecord] {
        var byTrack: [Int: [FrameDetection]] = [:]
        for d in detections { byTrack[d.trackID, default: []].append(d) }

        var records: [DefectRecord] = []
        var bestBoxes: [Int: CGRect] = [:]
        for (trackID, dets) in byTrack {
            guard dets.count >= minTrackLen else { continue }
            let sorted = dets.sorted { $0.timestamp < $1.timestamp }
            let best = dets.max { $0.confidence < $1.confidence }!

            var classCounts: [String: Int] = [:]
            for d in dets { classCounts[d.className, default: 0] += 1 }
            let majorityClass = classCounts.max { $0.value < $1.value }!.key

            var record = DefectRecord(
                trackID: trackID,
                className: majorityClass,
                confidence: best.confidence,
                firstSeenS: sorted.first!.timestamp,
                lastSeenS: sorted.last!.timestamp,
                nFrames: dets.count,
                cropFilename: nil,
                location: interpolate(gps: gps, at: sorted.first!.timestamp),
                dimensions: camera.flatMap { measure($0, best.bbox) }
            )
            record.cropFilename = "defect_\(trackID)_\(majorityClass).jpg"
            bestBoxes[trackID] = best.bbox
            records.append(record)
        }
        let ordered = records.sorted { $0.firstSeenS < $1.firstSeenS }
        let merged = mergeOverlappingClasses(ordered, boxes: bestBoxes)
        return dedupeByLocation(merged, radiusM: 8.0)
    }

    /// Collapse records that describe the same physical defect under
    /// different labels. The detector often fires Pothole and Crack on one
    /// patch of broken road; those arrive as separate tracks seen at the same
    /// moment with overlapping boxes. Keep the more confident label rather
    /// than reporting one defect twice.
    static func mergeOverlappingClasses(_ records: [DefectRecord],
                                        boxes: [Int: CGRect],
                                        iouThreshold: Double = 0.35,
                                        withinSeconds: TimeInterval = 0.75) -> [DefectRecord] {
        var kept: [DefectRecord] = []
        var dropped = Set<Int>()
        for i in records.indices where !dropped.contains(i) {
            var best = records[i]
            for j in (i + 1)..<records.count where !dropped.contains(j) {
                let o = records[j]
                guard o.className != best.className,
                      abs(o.firstSeenS - best.firstSeenS) <= withinSeconds,
                      let a = boxes[best.trackID], let b = boxes[o.trackID],
                      overlaps(a, b, iouThreshold: iouThreshold) else { continue }
                dropped.insert(j)
                if o.confidence > best.confidence { best = o }
            }
            kept.append(best)
        }
        return kept
    }

    /// Two boxes describe the same feature if they overlap substantially by
    /// IoU, or if one largely sits inside the other -- a wide Crack box often
    /// contains a small Pothole box, which IoU alone scores too low to catch.
    private static func overlaps(_ a: CGRect, _ b: CGRect, iouThreshold: Double) -> Bool {
        if iou(a, b) >= iouThreshold { return true }
        let inter = a.intersection(b)
        guard !inter.isNull, !inter.isEmpty else { return false }
        let ia = Double(inter.width * inter.height)
        let smaller = min(Double(a.width * a.height), Double(b.width * b.height))
        return smaller > 0 && ia / smaller >= 0.6
    }

    private static func iou(_ a: CGRect, _ b: CGRect) -> Double {
        let inter = a.intersection(b)
        guard !inter.isNull, !inter.isEmpty else { return 0 }
        let ia = Double(inter.width * inter.height)
        let ua = Double(a.width * a.height + b.width * b.height) - ia
        return ua > 0 ? ia / ua : 0
    }

    /// Merge same-class records within radiusM metres -- collapses a defect
    /// seen on a second pass or split across a tracking gap into one, keeping
    /// the highest-confidence record. Unlocated records pass through. Mirrors
    /// dedupe_by_location in pipeline/geo.py.
    ///
    /// Records seen at nearly the same moment are left alone: two defects
    /// beside each other interpolate to the same GPS fix, so distance cannot
    /// tell them apart. Only a genuine revisit -- the same place at a
    /// different time -- is a duplicate.
    static func dedupeByLocation(_ records: [DefectRecord], radiusM: Double,
                                 minRevisitGapS: TimeInterval = 2.0) -> [DefectRecord] {
        var kept: [DefectRecord] = []
        var dropped = Set<Int>()
        for i in records.indices {
            let r = records[i]
            guard let rloc = r.location else { kept.append(r); continue }
            if dropped.contains(i) { continue }
            var best = r
            for j in (i + 1)..<records.count {
                let o = records[j]
                guard !dropped.contains(j), o.className == r.className,
                      let oloc = o.location else { continue }
                guard abs(o.firstSeenS - r.firstSeenS) >= minRevisitGapS else { continue }
                if haversine(rloc.lat, rloc.lon, oloc.lat, oloc.lon) <= radiusM {
                    dropped.insert(j)
                    if o.confidence > best.confidence { best = o }
                }
            }
            kept.append(best)
        }
        return kept
    }

    private static func haversine(_ lat1: Double, _ lon1: Double,
                                  _ lat2: Double, _ lon2: Double) -> Double {
        let R = 6_371_000.0
        let p1 = lat1 * .pi / 180, p2 = lat2 * .pi / 180
        let dp = (lat2 - lat1) * .pi / 180, dl = (lon2 - lon1) * .pi / 180
        let a = sin(dp / 2) * sin(dp / 2) + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)
        return 2 * R * asin(min(1, sqrt(a)))
    }

    private static func interpolate(gps: [GpsFix], at t: TimeInterval) -> GeoPoint? {
        guard !gps.isEmpty else { return nil }
        let fixes = gps.sorted { $0.t < $1.t }
        if t <= fixes.first!.t {
            let f = fixes.first!
            return GeoPoint(lat: f.lat, lon: f.lon, heading: f.heading)
        }
        if t >= fixes.last!.t {
            let f = fixes.last!
            return GeoPoint(lat: f.lat, lon: f.lon, heading: f.heading)
        }
        var i = 0
        while i < fixes.count && fixes[i].t < t { i += 1 }
        let a = fixes[i - 1], b = fixes[i]
        let span = b.t - a.t
        let frac = span == 0 ? 0 : (t - a.t) / span
        let lat = a.lat + (b.lat - a.lat) * frac
        let lon = a.lon + (b.lon - a.lon) * frac
        let heading = a.heading ?? bearing(a.lat, a.lon, b.lat, b.lon)
        return GeoPoint(lat: lat, lon: lon, heading: heading)
    }

    private static func measure(_ cam: CameraModel, _ bbox: CGRect) -> Dimensions? {
        guard let d = Geometry.bboxDimensions(cam, bbox) else { return nil }
        return Dimensions(widthM: d.widthM, lengthM: d.lengthM,
                          areaM2: d.areaM2, distanceM: d.distanceM)
    }

    private static func bearing(_ lat1: Double, _ lon1: Double,
                                _ lat2: Double, _ lon2: Double) -> Double {
        let p1 = lat1 * .pi / 180, p2 = lat2 * .pi / 180
        let dl = (lon2 - lon1) * .pi / 180
        let x = sin(dl) * cos(p2)
        let y = cos(p1) * sin(p2) - sin(p1) * cos(p2) * cos(dl)
        return (atan2(x, y) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }
}
