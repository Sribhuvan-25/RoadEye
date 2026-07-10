#!/usr/bin/env python3
"""Produce a camera-config JSON (no calibration rig) from one video frame.

Grabs a frame, lets you mark the horizon by clicking on it (or pass the row
directly), derives intrinsics from the phone FOV and pitch from that horizon,
and writes the JSON that pipeline/track_and_dedup.py --camera-config expects.

Usage:
    # interactive: click the horizon line in the popped-up frame
    python scripts/make_camera_config.py --video drive.mp4 --height 1.3 --out camera.json

    # non-interactive: you already know the horizon pixel row
    python scripts/make_camera_config.py --video drive.mp4 --height 1.3 \
        --horizon-row 340 --out camera.json
"""
import argparse
import json
import sys
from dataclasses import asdict
from pathlib import Path

import cv2

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from pipeline.camera_setup import build_camera, PHONE_HFOV_DEG


def grab_frame(video_path: str, at_frac: float = 0.3):
    cap = cv2.VideoCapture(video_path)
    total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT)) or 1
    cap.set(cv2.CAP_PROP_POS_FRAMES, int(total * at_frac))
    ok, frame = cap.read()
    cap.release()
    if not ok:
        raise RuntimeError(f"could not read a frame from {video_path}")
    return frame


def pick_horizon_interactively(frame) -> float:
    """Show the frame; user clicks on the horizon. Returns the pixel row."""
    picked = {"row": None}

    def on_click(event, x, y, flags, param):
        if event == cv2.EVENT_LBUTTONDOWN:
            picked["row"] = y
            preview = frame.copy()
            cv2.line(preview, (0, y), (frame.shape[1], y), (0, 255, 0), 2)
            cv2.imshow("Click the horizon, then press any key", preview)

    cv2.imshow("Click the horizon, then press any key", frame)
    cv2.setMouseCallback("Click the horizon, then press any key", on_click)
    cv2.waitKey(0)
    cv2.destroyAllWindows()
    if picked["row"] is None:
        raise RuntimeError("no horizon clicked")
    return float(picked["row"])


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--video", required=True)
    parser.add_argument("--height", type=float, required=True,
                        help="camera height above the road, meters (eyeballed is fine)")
    parser.add_argument("--horizon-row", type=float,
                        help="horizon pixel row; omit to pick it interactively")
    parser.add_argument("--hfov", type=float, default=PHONE_HFOV_DEG["iphone_main"],
                        help="horizontal FOV in degrees (default: iPhone main camera)")
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    frame = grab_frame(args.video)
    h, w = frame.shape[:2]

    horizon_row = args.horizon_row
    if horizon_row is None:
        horizon_row = pick_horizon_interactively(frame)

    cam = build_camera(
        image_width=w, image_height=h,
        height_m=args.height, horizon_row_px=horizon_row, hfov_deg=args.hfov,
    )
    Path(args.out).write_text(json.dumps(asdict(cam), indent=2))
    print(f"Frame {w}x{h}, horizon row {horizon_row:.0f} -> pitch {cam.pitch_deg:.2f} deg")
    print(f"Wrote {args.out}")


if __name__ == "__main__":
    main()
