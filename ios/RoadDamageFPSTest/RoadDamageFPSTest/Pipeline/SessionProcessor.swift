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
            records.append(record)
        }
        let ordered = records.sorted { $0.firstSeenS < $1.firstSeenS }
        return dedupeByLocation(ordered, radiusM: 8.0)
    }

    /// Merge same-class records within radiusM metres -- collapses a defect
    /// seen on a second pass or split across a tracking gap into one, keeping
    /// the highest-confidence record. Unlocated records pass through. Mirrors
    /// dedupe_by_location in pipeline/geo.py.
    static func dedupeByLocation(_ records: [DefectRecord], radiusM: Double) -> [DefectRecord] {
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

    /// Linear interpolation between the two GPS fixes bracketing a time.
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
