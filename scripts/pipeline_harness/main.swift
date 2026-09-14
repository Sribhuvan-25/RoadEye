import Foundation
import CoreGraphics

/// Regression harness for the on-device capture pipeline, run on the Mac by
/// scripts/test_pipeline.sh. Covers the failures found on real device data:
/// horizon-grazing boxes reported as hundreds of metres, and every defect
/// collapsing onto one GPS fix because detections and GPS used different
/// clock origins.

var failures = 0
func check(_ label: String, _ condition: Bool) {
    print((condition ? "  ok   " : "  FAIL ") + label)
    if !condition { failures += 1 }
}

let cam = Geometry.makeCamera(imageWidth: 720, imageHeight: 1280,
                              heightM: 1.3, horizonRow: 1280 * 0.45)

print("[1] measurement plausibility")
check("sky box rejected",
      Geometry.bboxDimensions(cam, CGRect(x: 300, y: 300, width: 100, height: 80)) == nil)
check("horizon-grazing box rejected",
      Geometry.bboxDimensions(cam, CGRect(x: 330, y: 578, width: 60, height: 20)) == nil)
if let d = Geometry.bboxDimensions(cam, CGRect(x: 300, y: 800, width: 120, height: 90)) {
    check("mid-distance pothole measured", true)
    check("pothole area under 2 m2 (was 451 m2 on device)", d.areaM2 < 2.0)
    check("distance under 30 m", d.distanceM < 30)
} else {
    check("mid-distance pothole measured", false)
}

print("[2] track grouping + GPS")
var dets: [FrameDetection] = []
for i in 0..<30 {
    dets.append(FrameDetection(timestamp: Double(i) / 30.0, trackID: 1,
                               className: "Pothole", confidence: 0.5 + Double(i) * 0.01,
                               bbox: CGRect(x: 300, y: 800, width: 120, height: 90)))
}
for i in 0..<12 {
    dets.append(FrameDetection(timestamp: 4.0 + Double(i) / 30.0, trackID: 2,
                               className: "Crack", confidence: 0.6,
                               bbox: CGRect(x: 320, y: 820, width: 40, height: 130)))
}
dets.append(FrameDetection(timestamp: 2.0, trackID: 99, className: "Pothole",
                           confidence: 0.9, bbox: CGRect(x: 100, y: 900, width: 50, height: 50)))

let gps = (0...8).map { t in
    SessionProcessor.GpsFix(t: Double(t), lat: 33.9353,
                            lon: -84.3451 + Double(t) * 0.00009, heading: 90)
}
let records = SessionProcessor.buildRecords(detections: dets, gps: gps, camera: cam)
check("single-frame flicker dropped", records.count == 2)
check("all records geotagged", records.allSatisfy { $0.location != nil })
if records.count == 2, let a = records[0].location, let b = records[1].location {
    check("defects 4 s apart get different fixes", abs(a.lon - b.lon) > 1e-6)
}
check("all measured records are plausible",
      records.compactMap(\.dimensions).allSatisfy { $0.areaM2 <= Geometry.maxDefectAreaM2 })

print("[3] duplicate labels on one defect")
// The detector commonly fires two classes on the same patch of broken road.
// Those arrive as separate tracks, same moment, overlapping boxes.
let sharedBox = CGRect(x: 300, y: 800, width: 120, height: 90)
var dupes: [FrameDetection] = []
for i in 0..<10 {
    let t = Double(i) / 30.0
    dupes.append(FrameDetection(timestamp: t, trackID: 1, className: "Pothole",
                                confidence: 0.80, bbox: sharedBox))
    dupes.append(FrameDetection(timestamp: t, trackID: 2, className: "Crack",
                                confidence: 0.55,
                                bbox: sharedBox.insetBy(dx: -6, dy: -4)))
}
// A genuinely separate defect elsewhere in the frame must survive.
for i in 0..<10 {
    dupes.append(FrameDetection(timestamp: Double(i) / 30.0, trackID: 3,
                                className: "Pothole", confidence: 0.7,
                                bbox: CGRect(x: 60, y: 950, width: 80, height: 60)))
}
let deduped = SessionProcessor.buildRecords(detections: dupes, gps: gps, camera: cam)
check("overlapping Pothole+Crack merged into one", deduped.count == 2)
check("the more confident label wins",
      deduped.contains { $0.className == "Pothole" && $0.confidence >= 0.79 })
check("a separate defect is not swallowed",
      deduped.filter { $0.className == "Pothole" }.count == 2)

print("[4] a small box inside a large one is the same defect")
let wide = CGRect(x: 280, y: 780, width: 260, height: 130)   // Crack
let small = CGRect(x: 330, y: 810, width: 70, height: 60)    // Pothole inside it
var nested: [FrameDetection] = []
for i in 0..<10 {
    let t = Double(i) / 30.0
    nested.append(FrameDetection(timestamp: t, trackID: 1, className: "Crack",
                                 confidence: 0.60, bbox: wide))
    nested.append(FrameDetection(timestamp: t, trackID: 2, className: "Pothole",
                                 confidence: 0.75, bbox: small))
}
let nestedOut = SessionProcessor.buildRecords(detections: nested, gps: gps, camera: cam)
check("contained box merged despite low IoU", nestedOut.count == 1)
check("higher-confidence label kept", nestedOut.first?.className == "Pothole")

print(failures == 0 ? "\nALL PIPELINE CHECKS PASSED" : "\n\(failures) CHECK(S) FAILED")
exit(failures == 0 ? 0 : 1)
