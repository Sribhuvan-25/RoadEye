"""Phase 3: estimate real-world dimensions of road damage from pixel boxes.

Core idea (inverse perspective mapping): a camera at known height and pitch
looking at a flat road has a closed-form mapping from any image pixel (below
the horizon) to the ground-plane point it sees. Project a defect's bounding
box corners onto the ground and measure distances in meters.

Assumptions (and their consequences):
  * The road is locally flat -- true enough for length/width/area of surface
    damage; NOT sufficient for pothole depth (needs stereo/depth sensing).
  * Camera height and pitch are known and fixed (per-vehicle mount config).
  * The defect lies on the road plane -- valid for cracks/potholes/manholes,
    invalid for anything with height (cones, debris).

Frames:
  Camera: x right, y down (image convention), z forward along optical axis.
  World:  origin on the ground directly under the camera, X right,
          Y forward (driving direction), Z up.

Usage:
    cam = CameraModel(fx=800, fy=800, cx=640, cy=360,
                      height_m=1.4, pitch_deg=12.0)
    dims = estimate_bbox_dimensions(cam, bbox_xyxy=(500, 400, 700, 460))
    # -> BoxDimensions(width_m=..., length_m=..., area_m2=..., distance_m=...)
"""
import math
from dataclasses import dataclass
from typing import Optional


@dataclass
class CameraModel:
    fx: float          # focal length in pixels
    fy: float
    cx: float          # principal point (usually image center)
    cy: float
    height_m: float    # camera height above road surface
    pitch_deg: float   # downward tilt from horizontal (0 = looking at horizon)

    @property
    def pitch_rad(self) -> float:
        return math.radians(self.pitch_deg)


@dataclass
class BoxDimensions:
    width_m: float       # across the driving direction
    length_m: float      # along the driving direction
    area_m2: float       # width * length (rectangular approximation)
    distance_m: float    # ground distance from camera to the near edge


def pixel_to_ground(cam: CameraModel, u: float, v: float) -> Optional[tuple]:
    """Map an image pixel to its (X, Y) ground-plane point in meters.

    Returns None for pixels on or above the horizon (ray never hits ground).
    """
    # ray direction in camera coordinates
    dx = (u - cam.cx) / cam.fx
    dy = (v - cam.cy) / cam.fy
    dz = 1.0

    s, c = math.sin(cam.pitch_rad), math.cos(cam.pitch_rad)
    # world-frame ray components (camera axes expressed in world frame):
    #   cam x -> (1, 0, 0)
    #   cam y -> (0, -s, -c)   (image "down" maps forward-down once pitched)
    #   cam z -> (0,  c, -s)
    ray_z = -(dy * c + dz * s)          # vertical component
    if ray_z >= -1e-9:                  # pointing at/above horizon
        return None
    t = cam.height_m / (dy * c + dz * s)  # = -h / ray_z, positive here
    ground_x = t * dx
    ground_y = t * (-dy * s + dz * c)
    return (ground_x, ground_y)


def ground_to_pixel(cam: CameraModel, ground_x: float, ground_y: float) -> tuple:
    """Forward projection (world ground point -> pixel). Used for validation."""
    # point relative to camera center (0, 0, h), expressed on camera axes
    px, py, pz = ground_x, ground_y, -cam.height_m
    s, c = math.sin(cam.pitch_rad), math.cos(cam.pitch_rad)
    x_cam = px
    y_cam = py * (-s) + pz * (-c)
    z_cam = py * c + pz * (-s)
    if z_cam <= 0:
        raise ValueError("point is behind the camera")
    u = cam.fx * x_cam / z_cam + cam.cx
    v = cam.fy * y_cam / z_cam + cam.cy
    return (u, v)


def estimate_bbox_dimensions(
    cam: CameraModel, bbox_xyxy: tuple
) -> Optional[BoxDimensions]:
    """Convert a pixel bounding box to real-world size on the road plane.

    Width is measured along the bottom edge (nearest to the camera, where
    the box meets the road most reliably); length along the left/right
    edges averaged. Returns None if any needed corner maps above horizon.
    """
    x1, y1, x2, y2 = bbox_xyxy

    bl = pixel_to_ground(cam, x1, y2)   # bottom-left
    br = pixel_to_ground(cam, x2, y2)   # bottom-right
    tl = pixel_to_ground(cam, x1, y1)   # top-left
    tr = pixel_to_ground(cam, x2, y1)   # top-right
    if any(p is None for p in (bl, br, tl, tr)):
        return None

    width_m = math.dist(bl, br)
    length_m = (math.dist(bl, tl) + math.dist(br, tr)) / 2
    near_mid = ((bl[0] + br[0]) / 2, (bl[1] + br[1]) / 2)
    distance_m = math.hypot(*near_mid)

    return BoxDimensions(
        width_m=width_m,
        length_m=length_m,
        area_m2=width_m * length_m,
        distance_m=distance_m,
    )


def estimate_quad_dimensions(
    cam: CameraModel, corners_px: list
) -> Optional[BoxDimensions]:
    """Like estimate_bbox_dimensions but from 4 explicit corner pixels
    (bl, br, tl, tr order). Exact for flat quadrilaterals -- use this
    instead of the bbox variant when a segmentation mask (or oriented box)
    is available; it does not suffer the axis-aligned-bbox skew error.
    """
    pts = [pixel_to_ground(cam, u, v) for u, v in corners_px]
    if any(p is None for p in pts):
        return None
    bl, br, tl, tr = pts
    width_m = (math.dist(bl, br) + math.dist(tl, tr)) / 2
    length_m = (math.dist(bl, tl) + math.dist(br, tr)) / 2
    near_mid = ((bl[0] + br[0]) / 2, (bl[1] + br[1]) / 2)
    return BoxDimensions(
        width_m=width_m,
        length_m=length_m,
        area_m2=width_m * length_m,
        distance_m=math.hypot(*near_mid),
    )


# ---------------------------------------------------------------------------
# Self-validation with synthetic geometry: place rectangles of KNOWN size on
# the ground, forward-project them into the image, then check the inverse
# mapping. Two tiers:
#   1. Quad round-trip (exact corners) -- validates the core IPM math;
#      must be near-zero error or the geometry is wrong.
#   2. Axis-aligned bbox estimates -- what we get from a real detector;
#      inherits a known overestimation for narrow objects offset from
#      image center (the bbox spans more ground than the skewed object).
#      Reported to quantify the limitation, not asserted tight.
# ---------------------------------------------------------------------------

def _self_test() -> None:
    cam = CameraModel(
        fx=800.0, fy=800.0, cx=640.0, cy=360.0,   # 1280x720-ish camera
        height_m=1.4, pitch_deg=12.0,              # typical windshield mount
    )

    test_rects = [
        # (center_forward_m, center_right_m, width_m, length_m)
        (5.0, 0.0, 0.60, 0.40),     # pothole-sized, dead ahead, close
        (8.0, 1.0, 0.60, 0.40),     # same size, offset right, farther
        (12.0, -1.5, 1.20, 0.80),   # larger patch, offset left, far
        (4.0, 0.5, 0.15, 0.90),     # narrow long crack, offset (bbox worst case)
    ]

    print(f"Camera: h={cam.height_m}m pitch={cam.pitch_deg}deg "
          f"f={cam.fx}px c=({cam.cx},{cam.cy})")

    # --- tier 1: exact-corner round trip (validates the IPM math itself) ---
    print("\nTier 1 -- quad corners (exact):")
    print(f"{'true WxL':>14} {'recovered WxL':>16} {'err%':>12}")
    max_quad_err = 0.0
    for fwd, right, w, l in test_rects:
        bl = ground_to_pixel(cam, right - w / 2, fwd - l / 2)
        br = ground_to_pixel(cam, right + w / 2, fwd - l / 2)
        tl = ground_to_pixel(cam, right - w / 2, fwd + l / 2)
        tr = ground_to_pixel(cam, right + w / 2, fwd + l / 2)
        dims = estimate_quad_dimensions(cam, [bl, br, tl, tr])
        assert dims is not None
        w_err = abs(dims.width_m - w) / w * 100
        l_err = abs(dims.length_m - l) / l * 100
        max_quad_err = max(max_quad_err, w_err, l_err)
        print(
            f"{w:.2f}x{l:.2f}m".rjust(14),
            f"{dims.width_m:.3f}x{dims.length_m:.3f}m".rjust(16),
            f"w{w_err:.2f} l{l_err:.2f}".rjust(12),
        )
    assert max_quad_err < 0.1, (
        f"quad round-trip error {max_quad_err:.2f}% -- core IPM geometry is broken"
    )
    print(f"IPM math exact to {max_quad_err:.4f}%")

    # --- tier 2: axis-aligned bbox (what a detector actually gives us) ---
    print("\nTier 2 -- axis-aligned bbox (detector reality):")
    print(f"{'true WxL':>14} {'recovered WxL':>16} {'err%':>12} {'dist_m':>7}")
    for fwd, right, w, l in test_rects:
        corners_world = [
            (right - w / 2, fwd - l / 2),
            (right + w / 2, fwd - l / 2),
            (right - w / 2, fwd + l / 2),
            (right + w / 2, fwd + l / 2),
        ]
        pixels = [ground_to_pixel(cam, gx, gy) for gx, gy in corners_world]
        us = [p[0] for p in pixels]
        vs = [p[1] for p in pixels]
        bbox = (min(us), min(vs), max(us), max(vs))
        dims = estimate_bbox_dimensions(cam, bbox)
        assert dims is not None
        w_err = abs(dims.width_m - w) / w * 100
        l_err = abs(dims.length_m - l) / l * 100
        print(
            f"{w:.2f}x{l:.2f}m".rjust(14),
            f"{dims.width_m:.3f}x{dims.length_m:.3f}m".rjust(16),
            f"w{w_err:.1f} l{l_err:.1f}".rjust(12),
            f"{dims.distance_m:.1f}".rjust(7),
        )
    print(
        "\nNote: bbox width overestimates for narrow objects offset from image\n"
        "center (axis-aligned box spans more ground than the skewed object).\n"
        "Dead-ahead objects are near-exact. For cracks, prefer segmentation\n"
        "masks + estimate_quad_dimensions, or report bbox dims as upper bounds."
    )


if __name__ == "__main__":
    _self_test()
