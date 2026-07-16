import CoreGraphics
import Foundation

/// On-device inverse perspective mapping -- Swift port of pipeline/camera_setup.py
/// and pipeline/dimension_estimation.py (validated exact against synthetic
/// geometry there). Projects pixel bounding boxes onto the flat road plane to
/// estimate real-world size, with no calibration rig: intrinsics from the
/// camera FOV, pitch from the horizon line, height supplied by the user.

struct CameraModel {
    var fx: Double
    var fy: Double
    var cx: Double
    var cy: Double
    var heightM: Double
    var pitchDeg: Double

    var pitchRad: Double { pitchDeg * .pi / 180 }
}

struct BoxDimensions {
    var widthM: Double
    var lengthM: Double
    var areaM2: Double
    var distanceM: Double
}

enum Geometry {
    static let iphoneMainHFOVDeg = 68.0

    static func intrinsicsFromFOV(
        imageWidth: Int, imageHeight: Int, hfovDeg: Double = iphoneMainHFOVDeg
    ) -> (fx: Double, fy: Double, cx: Double, cy: Double) {
        let w = Double(imageWidth), h = Double(imageHeight)
        let fx = (w / 2) / tan(hfovDeg * .pi / 180 / 2)
        return (fx, fx, w / 2, h / 2)
    }

    static func pitchFromHorizon(horizonRow: Double, cy: Double, fy: Double) -> Double {
        atan((cy - horizonRow) / fy) * 180 / .pi
    }

    static func makeCamera(
        imageWidth: Int, imageHeight: Int, heightM: Double,
        horizonRow: Double, hfovDeg: Double = iphoneMainHFOVDeg
    ) -> CameraModel {
        let k = intrinsicsFromFOV(imageWidth: imageWidth, imageHeight: imageHeight, hfovDeg: hfovDeg)
        let pitch = pitchFromHorizon(horizonRow: horizonRow, cy: k.cy, fy: k.fy)
        return CameraModel(fx: k.fx, fy: k.fy, cx: k.cx, cy: k.cy, heightM: heightM, pitchDeg: pitch)
    }

    static func pixelToGround(_ cam: CameraModel, u: Double, v: Double) -> (x: Double, y: Double)? {
        let dx = (u - cam.cx) / cam.fx
        let dy = (v - cam.cy) / cam.fy
        let dz = 1.0
        let s = sin(cam.pitchRad), c = cos(cam.pitchRad)
        let denom = dy * c + dz * s
        if denom <= 1e-9 { return nil }
        let t = cam.heightM / denom
        return (t * dx, t * (-dy * s + dz * c))
    }

    /// Convert a pixel bbox (x1,y1,x2,y2) to real-world size on the road plane.
    /// Nil if any corner maps above the horizon. Width along the near (bottom)
    /// edge where the box meets the road most reliably; for narrow off-center
    /// defects bbox width is an upper bound (see the Python reference).
    static func bboxDimensions(_ cam: CameraModel, _ box: CGRect) -> BoxDimensions? {
        let x1 = Double(box.minX), y1 = Double(box.minY)
        let x2 = Double(box.maxX), y2 = Double(box.maxY)
        guard let bl = pixelToGround(cam, u: x1, v: y2),
              let br = pixelToGround(cam, u: x2, v: y2),
              let tl = pixelToGround(cam, u: x1, v: y1),
              let tr = pixelToGround(cam, u: x2, v: y1) else { return nil }

        let width = dist(bl, br)
        let length = (dist(bl, tl) + dist(br, tr)) / 2
        let nearMid = ((bl.x + br.x) / 2, (bl.y + br.y) / 2)
        let distance = (nearMid.0 * nearMid.0 + nearMid.1 * nearMid.1).squareRoot()
        return BoxDimensions(widthM: width, lengthM: length,
                             areaM2: width * length, distanceM: distance)
    }

    private static func dist(_ a: (x: Double, y: Double), _ b: (x: Double, y: Double)) -> Double {
        let dx = a.x - b.x, dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }
}
