"""Phase 2: turn a video + detector into one record per physical defect.

A pothole visible for 30 frames should become ONE entry, not 30. This module
runs the detector with Ultralytics' built-in multi-object tracker (ByteTrack
by default) across a video, groups detections by track ID, and for each
track emits a single DefectRecord: best (highest-confidence) frame crop,
majority-vote class, confidence, and the pixel bbox at that best frame.

GPS/IMU tagging is a stub for now (no hardware feed yet -- Phase 4 wires
this to real location data during capture). `gps_lookup` lets a caller
inject a function that maps timestamp -> (lat, lon, heading) once that
exists; without one, records simply carry no location.

Usage:
    python -m pipeline.track_and_dedup --video drive.mp4 \
        --model models/best.pt --out out/session_001
"""
import argparse
import json
from collections import defaultdict
from dataclasses import dataclass, field, asdict
from pathlib import Path
from typing import Callable, Optional

import cv2
from ultralytics import YOLO

from pipeline.dimension_estimation import CameraModel, estimate_bbox_dimensions
from pipeline.geo import (
    dedupe_by_location,
    load_csv,
    load_gpx,
    make_gps_lookup,
    write_geojson,
)


@dataclass
class Detection:
    frame_idx: int
    timestamp_s: float
    track_id: int
    cls_id: int
    cls_name: str
    conf: float
    xyxy: tuple  # pixel coords in the source frame


@dataclass
class DefectRecord:
    track_id: int
    cls_name: str
    conf: float
    first_seen_s: float
    last_seen_s: float
    n_frames: int
    best_frame_idx: int
    best_xyxy: tuple
    crop_path: Optional[str] = None
    location: Optional[dict] = field(default=None)  # {"lat":.., "lon":.., "heading":..}
    # real-world size via IPM when a CameraModel is supplied; width/length in
    # meters, area m^2, distance from camera at best frame. For narrow
    # off-center defects (cracks) bbox-based width is an UPPER BOUND -- see
    # pipeline/dimension_estimation.py.
    dimensions: Optional[dict] = field(default=None)


def run_tracker(
    video_path: str,
    model_path: str,
    conf: float = 0.25,
    tracker: str = "bytetrack.yaml",
    imgsz: int = 640,
) -> list[Detection]:
    """Stream a video through the detector+tracker, return every raw detection."""
    model = YOLO(model_path)
    cap = cv2.VideoCapture(video_path)
    fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    cap.release()

    detections = []
    results = model.track(
        source=video_path,
        conf=conf,
        tracker=tracker,
        imgsz=imgsz,
        stream=True,
        persist=True,
        verbose=False,
    )
    for frame_idx, r in enumerate(results):
        if r.boxes is None or r.boxes.id is None:
            continue  # no tracked detections this frame
        for box in r.boxes:
            track_id = int(box.id[0])
            cls_id = int(box.cls[0])
            detections.append(
                Detection(
                    frame_idx=frame_idx,
                    timestamp_s=frame_idx / fps,
                    track_id=track_id,
                    cls_id=cls_id,
                    cls_name=model.names[cls_id],
                    conf=float(box.conf[0]),
                    xyxy=tuple(float(v) for v in box.xyxy[0]),
                )
            )
    return detections


def group_into_defects(
    detections: list[Detection],
    min_track_len: int = 2,
) -> list[DefectRecord]:
    """Collapse per-frame detections sharing a track ID into one record each.

    min_track_len filters out single-frame flickers (a track seen in only
    one frame is more likely noise than a real, persistent defect) --
    tune per how noisy the detector is in practice.
    """
    by_track: dict[int, list[Detection]] = defaultdict(list)
    for d in detections:
        by_track[d.track_id].append(d)

    records = []
    for track_id, dets in by_track.items():
        if len(dets) < min_track_len:
            continue
        dets.sort(key=lambda d: d.timestamp_s)
        best = max(dets, key=lambda d: d.conf)
        # majority-vote class in case the tracker ever flips class mid-track
        cls_counts: dict[str, int] = defaultdict(int)
        for d in dets:
            cls_counts[d.cls_name] += 1
        majority_cls = max(cls_counts, key=cls_counts.get)

        records.append(
            DefectRecord(
                track_id=track_id,
                cls_name=majority_cls,
                conf=best.conf,
                first_seen_s=dets[0].timestamp_s,
                last_seen_s=dets[-1].timestamp_s,
                n_frames=len(dets),
                best_frame_idx=best.frame_idx,
                best_xyxy=best.xyxy,
            )
        )
    return records


def save_crops(
    video_path: str,
    records: list[DefectRecord],
    out_dir: Path,
    padding_frac: float = 0.15,
) -> None:
    """Extract the best frame's crop for each defect record, write to disk."""
    out_dir.mkdir(parents=True, exist_ok=True)
    frame_targets = {r.best_frame_idx: r for r in records}

    cap = cv2.VideoCapture(video_path)
    frame_idx = 0
    while frame_targets:
        ok, frame = cap.read()
        if not ok:
            break
        if frame_idx in frame_targets:
            r = frame_targets.pop(frame_idx)
            h, w = frame.shape[:2]
            x1, y1, x2, y2 = r.best_xyxy
            bw, bh = x2 - x1, y2 - y1
            x1 = max(0, int(x1 - bw * padding_frac))
            y1 = max(0, int(y1 - bh * padding_frac))
            x2 = min(w, int(x2 + bw * padding_frac))
            y2 = min(h, int(y2 + bh * padding_frac))
            crop = frame[y1:y2, x1:x2]
            crop_path = out_dir / f"defect_{r.track_id:04d}_{r.cls_name}.jpg"
            cv2.imwrite(str(crop_path), crop)
            r.crop_path = str(crop_path)
        frame_idx += 1
    cap.release()


def attach_locations(
    records: list[DefectRecord],
    gps_lookup: Optional[Callable[[float], dict]] = None,
) -> None:
    """Fill in record.location via gps_lookup(timestamp_s) -> {"lat","lon","heading"}.

    No-op stub until Phase 4 wires up a real GPS/IMU feed during capture.
    """
    if gps_lookup is None:
        return
    for r in records:
        r.location = gps_lookup(r.first_seen_s)


def attach_dimensions(
    records: list[DefectRecord],
    camera: Optional[CameraModel] = None,
) -> None:
    """Fill in record.dimensions via IPM from each record's best-frame bbox.

    No-op without a camera config (height/pitch/intrinsics are per-vehicle
    mount properties that must come from calibration).
    """
    if camera is None:
        return
    for r in records:
        dims = estimate_bbox_dimensions(camera, r.best_xyxy)
        if dims is not None:
            r.dimensions = {
                "width_m": round(dims.width_m, 3),
                "length_m": round(dims.length_m, 3),
                "area_m2": round(dims.area_m2, 3),
                "distance_m": round(dims.distance_m, 1),
            }


def process_video(
    video_path: str,
    model_path: str,
    out_dir: str,
    conf: float = 0.25,
    min_track_len: int = 2,
    gps_lookup: Optional[Callable[[float], dict]] = None,
    camera: Optional[CameraModel] = None,
    dedup_radius_m: Optional[float] = None,
) -> list[DefectRecord]:
    out_path = Path(out_dir)
    out_path.mkdir(parents=True, exist_ok=True)

    detections = run_tracker(video_path, model_path, conf=conf)
    print(f"{len(detections)} raw detections across all frames")

    records = group_into_defects(detections, min_track_len=min_track_len)
    print(f"-> {len(records)} unique defect tracks after grouping")

    save_crops(video_path, records, out_path / "crops")
    attach_locations(records, gps_lookup)
    attach_dimensions(records, camera)

    if dedup_radius_m and gps_lookup is not None:
        before = len(records)
        records = dedupe_by_location(records, radius_m=dedup_radius_m)
        print(f"-> {len(records)} after spatial dedup ({before - len(records)} merged)")

    manifest_path = out_path / "defects.json"
    manifest_path.write_text(
        json.dumps([asdict(r) for r in records], indent=2)
    )
    print(f"Wrote {manifest_path}")

    if gps_lookup is not None:
        n = write_geojson(records, out_path / "defects.geojson")
        print(f"Wrote {out_path / 'defects.geojson'} ({n} located features)")

    return records


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--video", required=True)
    parser.add_argument("--model", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--conf", type=float, default=0.25)
    parser.add_argument("--min-track-len", type=int, default=2)
    parser.add_argument(
        "--camera-config",
        help="JSON file with fx, fy, cx, cy, height_m, pitch_deg -- enables "
        "real-world dimension estimates on each defect record",
    )
    parser.add_argument("--gps", help="GPS log (.gpx or .csv) to geotag defects")
    parser.add_argument("--gps-offset", type=float, default=0.0,
                        help="seconds to add to video time to align it with the GPS clock")
    parser.add_argument("--dedup-radius", type=float, default=8.0,
                        help="merge same-class defects within this many metres (needs --gps)")
    args = parser.parse_args()

    camera = None
    if args.camera_config:
        cfg = json.loads(Path(args.camera_config).read_text())
        camera = CameraModel(**cfg)

    gps_lookup = None
    if args.gps:
        fixes = load_gpx(args.gps) if args.gps.lower().endswith(".gpx") else load_csv(args.gps)
        gps_lookup = make_gps_lookup(fixes, time_offset_s=args.gps_offset)

    process_video(
        video_path=args.video,
        model_path=args.model,
        out_dir=args.out,
        conf=args.conf,
        min_track_len=args.min_track_len,
        camera=camera,
        gps_lookup=gps_lookup,
        dedup_radius_m=args.dedup_radius,
    )


if __name__ == "__main__":
    main()
