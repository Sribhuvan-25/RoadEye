"""Build a CameraModel for a phone main camera without a calibration rig.

Intrinsics come from the camera's known field of view; pitch is recovered
from the horizon line in the footage (its largest error source, so we read
it from the image rather than guess). Height must be supplied -- it scales
every measurement linearly; an eyeballed dashboard height is fine to start.
"""
import math
from typing import Optional

from pipeline.dimension_estimation import CameraModel

PHONE_HFOV_DEG = {
    "iphone_main": 68.0,   # iPhone 12-17 main/wide, ~26mm equiv
    "generic_wide": 70.0,
}


def intrinsics_from_fov(
    image_width: int,
    image_height: int,
    hfov_deg: float = PHONE_HFOV_DEG["iphone_main"],
) -> tuple:
    """(fx, fy, cx, cy) in pixels from horizontal FOV + resolution; square pixels."""
    fx = (image_width / 2) / math.tan(math.radians(hfov_deg) / 2)
    fy = fx
    cx = image_width / 2
    cy = image_height / 2
    return fx, fy, cx, cy


def pitch_from_horizon(horizon_row_px: float, cy: float, fy: float) -> float:
    """Pitch (deg, downward positive) from the horizon's pixel row.

    Zero pitch puts the horizon at cy; tilting down raises it toward the top.
    """
    return math.degrees(math.atan((cy - horizon_row_px) / fy))


def build_camera(
    image_width: int,
    image_height: int,
    height_m: float,
    pitch_deg: Optional[float] = None,
    horizon_row_px: Optional[float] = None,
    hfov_deg: float = PHONE_HFOV_DEG["iphone_main"],
) -> CameraModel:
    """Assemble a CameraModel from FOV + height, with pitch given directly
    or derived from a horizon pixel row. Exactly one of pitch_deg /
    horizon_row_px must be provided.
    """
    if (pitch_deg is None) == (horizon_row_px is None):
        raise ValueError("provide exactly one of pitch_deg or horizon_row_px")

    fx, fy, cx, cy = intrinsics_from_fov(image_width, image_height, hfov_deg)
    if pitch_deg is None:
        pitch_deg = pitch_from_horizon(horizon_row_px, cy, fy)

    return CameraModel(
        fx=fx, fy=fy, cx=cx, cy=cy, height_m=height_m, pitch_deg=pitch_deg
    )


if __name__ == "__main__":
    cam = build_camera(
        image_width=1080, image_height=1920,
        height_m=1.3, horizon_row_px=900,
    )
    print(f"fx={cam.fx:.1f}px  cx={cam.cx:.0f} cy={cam.cy:.0f}")
    print(f"derived pitch={cam.pitch_deg:.2f} deg  height={cam.height_m} m")
