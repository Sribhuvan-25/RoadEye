#!/usr/bin/env python3
"""Build a short synthetic 'approach' video from a still image, for testing
pipeline/track_and_dedup.py end-to-end before real dashcam video exists.

Simulates a vehicle approaching a pothole: a slow zoom-in (crop shrinks,
gets rescaled up) over N frames, so a real detected defect grows larger
frame over frame -- enough motion for a tracker to follow, unlike a static
repeated frame.

Usage:
    python scripts/make_synthetic_test_video.py \
        --image data/processed/potholes-cracks-manholes/val/images/XYZ.jpg \
        --out logs/synthetic_test.mp4 --seconds 4 --fps 15
"""
import argparse

import cv2
import numpy as np


def make_zoom_video(image_path: str, out_path: str, seconds: float, fps: int) -> None:
    img = cv2.imread(image_path)
    if img is None:
        raise FileNotFoundError(image_path)
    h, w = img.shape[:2]
    n_frames = int(seconds * fps)

    fourcc = cv2.VideoWriter_fourcc(*"mp4v")
    writer = cv2.VideoWriter(out_path, fourcc, fps, (w, h))

    # zoom from 100% (full frame) down to 55% (crop tightens toward center-bottom,
    # roughly where road surface + damage sits in these dashcam-style shots)
    start_scale, end_scale = 1.0, 0.55
    cx, cy = 0.5, 0.62  # crop center as a fraction of width/height

    for i in range(n_frames):
        t = i / max(n_frames - 1, 1)
        scale = start_scale + (end_scale - start_scale) * t
        crop_w, crop_h = int(w * scale), int(h * scale)
        x0 = int(cx * w - crop_w / 2)
        y0 = int(cy * h - crop_h / 2)
        x0 = max(0, min(w - crop_w, x0))
        y0 = max(0, min(h - crop_h, y0))
        crop = img[y0 : y0 + crop_h, x0 : x0 + crop_w]
        frame = cv2.resize(crop, (w, h), interpolation=cv2.INTER_LINEAR)
        writer.write(frame)

    writer.release()
    print(f"Wrote {n_frames} frames ({seconds}s @ {fps}fps) to {out_path}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--image", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--seconds", type=float, default=4.0)
    parser.add_argument("--fps", type=int, default=15)
    args = parser.parse_args()
    make_zoom_video(args.image, args.out, args.seconds, args.fps)


if __name__ == "__main__":
    main()
