"""Build the structured payload the LLM narrates.

The LLM sees ONLY this object: a complete, precomputed view of the session.
Every number, count, ordering, and severity is decided here in code so the
model has nothing to invent -- its job is prose, not arithmetic. Loading is
tolerant of both the Python pipeline's snake_case defects.json and the Swift
app's camelCase DefectRecord encoding, so the same reporter serves both.
"""
import json
from collections import Counter, defaultdict
from pathlib import Path
from typing import Optional

from report import severity


def _get(d: dict, *keys, default=None):
    """First present key among aliases (snake_case / camelCase)."""
    for k in keys:
        if k in d and d[k] is not None:
            return d[k]
    return default


def _norm_dimensions(dims: Optional[dict]) -> Optional[dict]:
    """Normalize a dimensions dict to snake_case metres, or None."""
    if not dims:
        return None
    width = _get(dims, "width_m", "widthM")
    length = _get(dims, "length_m", "lengthM")
    area = _get(dims, "area_m2", "areaM2")
    distance = _get(dims, "distance_m", "distanceM")
    if width is None and length is None and area is None:
        return None
    return {
        "width_m": _round(width),
        "length_m": _round(length),
        "area_m2": _round(area),
        "distance_m": _round(distance, 1),
    }


def _norm_location(loc: Optional[dict]) -> Optional[dict]:
    if not loc:
        return None
    lat = _get(loc, "lat")
    lon = _get(loc, "lon")
    if lat is None or lon is None:
        return None
    return {
        "lat": round(float(lat), 6),
        "lon": round(float(lon), 6),
        "heading_deg": _round(_get(loc, "heading", "heading_deg"), 1),
    }


def _round(v, ndigits=2):
    return None if v is None else round(float(v), ndigits)


def _norm_record(raw: dict) -> dict:
    """One raw defect dict -> normalized record with severity attached."""
    cls = _get(raw, "cls_name", "className", default="unknown")
    dims = _norm_dimensions(_get(raw, "dimensions"))
    sev = severity.score(cls, dims)
    return {
        "id": _get(raw, "track_id", "trackID"),
        "class": cls,
        "confidence": _round(_get(raw, "conf", "confidence"), 3),
        "n_frames": _get(raw, "n_frames", "nFrames"),
        "dimensions": dims,
        "location": _norm_location(_get(raw, "location")),
        "severity": sev["level"],
        "severity_reason": sev["reason"],
    }


def build_payload(
    defects: list,
    session_id: str,
    started_epoch: Optional[float] = None,
    duration_s: Optional[float] = None,
) -> dict:
    """Assemble the full LLM input payload from raw defect dicts + session meta.

    Returns a dict with: session metadata, per-class and per-severity counts,
    the severity-then-size ordered defect list, and explicit data-quality flags
    (how many defects lack measurement or location). Everything the report
    states traces to a field in here.
    """
    records = [_norm_record(d) for d in defects]

    def sort_key(r):
        rank = severity.LEVEL_RANK.get(r["severity"], 0)
        dims = r["dimensions"] or {}
        size = dims.get("area_m2") or dims.get("length_m") or 0.0
        return (-rank, -size)

    records.sort(key=sort_key)

    by_class = Counter(r["class"] for r in records)
    by_severity = Counter(r["severity"] for r in records)

    unmeasured = sum(1 for r in records if r["dimensions"] is None)
    unlocated = sum(1 for r in records if r["location"] is None)

    total_area = round(
        sum((r["dimensions"] or {}).get("area_m2") or 0.0 for r in records), 2
    )

    return {
        "session": {
            "session_id": session_id,
            "started_epoch": started_epoch,
            "duration_s": _round(duration_s, 1),
            "defect_count": len(records),
        },
        "counts": {
            "by_class": dict(by_class),
            "by_severity": {lv: by_severity.get(lv, 0) for lv in severity.LEVELS},
            "total_measured_area_m2": total_area,
        },
        "data_quality": {
            "unmeasured_count": unmeasured,
            "unlocated_count": unlocated,
            "measurement_method": "inverse perspective mapping (IPM); "
            "dimensions pending field validation",
        },
        "severity_scale": {
            "definition": "computed deterministically from class + measured "
            "size; pothole by area (m^2), crack by length (m); manhole and "
            "unmeasured defects are 'low' / unassessed",
            "levels": severity.LEVELS,
        },
        "defects": records,
    }


def load_defects(path: str) -> list:
    """Load a defects.json (list of record dicts) from disk."""
    data = json.loads(Path(path).read_text())
    if not isinstance(data, list):
        raise ValueError(f"{path}: expected a JSON list of defect records")
    return data
