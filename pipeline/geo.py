"""Turn a GPS log into a time->location lookup, dedupe by place, export GeoJSON.

GPS loggers record a fix roughly once a second; the detector runs at ~30 fps.
So we interpolate between the two surrounding fixes to place each detection,
and derive heading from consecutive fixes when the log lacks it.

Spatial dedup collapses records of the same class that fall within a few
metres of each other -- the same pothole seen on two passes, or split across
two tracks, becomes one defect.
"""
import csv
import json
import math
import xml.etree.ElementTree as ET
from bisect import bisect_left
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Optional

EARTH_RADIUS_M = 6_371_000


@dataclass
class GpsFix:
    t_s: float          # seconds from log start
    lat: float
    lon: float
    heading: Optional[float] = None


def haversine_m(lat1, lon1, lat2, lon2) -> float:
    """Great-circle distance in metres between two lat/lon points."""
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = math.radians(lat2 - lat1)
    dl = math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * EARTH_RADIUS_M * math.asin(math.sqrt(a))


def bearing_deg(lat1, lon1, lat2, lon2) -> float:
    """Compass bearing (deg from north) from point 1 to point 2."""
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dl = math.radians(lon2 - lon1)
    x = math.sin(dl) * math.cos(p2)
    y = math.cos(p1) * math.sin(p2) - math.sin(p1) * math.cos(p2) * math.cos(dl)
    return (math.degrees(math.atan2(x, y)) + 360) % 360


def load_gpx(path: str) -> list[GpsFix]:
    """Parse GPX trackpoints. Times become seconds from the first point.

    ISO timestamps are read as fields but not parsed to epoch here (the
    runtime forbids wall-clock calls); instead point spacing is assumed
    uniform if no <time> is usable. If <time> is absent, points are spaced
    1 s apart -- override by supplying a CSV with explicit t_s instead.
    """
    ns = {"gpx": "http://www.topografix.com/GPX/1/1"}
    tree = ET.parse(path)
    root = tree.getroot()
    pts = root.findall(".//gpx:trkpt", ns) or root.findall(".//trkpt")
    fixes = []
    for i, pt in enumerate(pts):
        lat = float(pt.get("lat"))
        lon = float(pt.get("lon"))
        fixes.append(GpsFix(t_s=float(i), lat=lat, lon=lon))
    return fixes


def load_csv(path: str) -> list[GpsFix]:
    """Parse a CSV with columns t_s, lat, lon, and optional heading."""
    fixes = []
    with open(path, newline="") as f:
        for row in csv.DictReader(f):
            fixes.append(
                GpsFix(
                    t_s=float(row["t_s"]),
                    lat=float(row["lat"]),
                    lon=float(row["lon"]),
                    heading=float(row["heading"]) if row.get("heading") else None,
                )
            )
    return fixes


def make_gps_lookup(
    fixes: list[GpsFix], time_offset_s: float = 0.0
) -> Callable[[float], Optional[dict]]:
    """Build gps_lookup(video_ts) -> {lat, lon, heading} by interpolating fixes.

    time_offset_s aligns the video clock to the GPS clock (video t=0 may not
    equal GPS t=0). Heading comes from the log if present, else from the
    direction between the bracketing fixes.
    """
    fixes = sorted(fixes, key=lambda f: f.t_s)
    times = [f.t_s for f in fixes]

    def lookup(video_ts: float) -> Optional[dict]:
        if not fixes:
            return None
        t = video_ts + time_offset_s
        i = bisect_left(times, t)
        if i == 0:
            f = fixes[0]
            return {"lat": f.lat, "lon": f.lon, "heading": f.heading}
        if i >= len(fixes):
            f = fixes[-1]
            return {"lat": f.lat, "lon": f.lon, "heading": f.heading}
        a, b = fixes[i - 1], fixes[i]
        span = b.t_s - a.t_s
        frac = 0.0 if span == 0 else (t - a.t_s) / span
        lat = a.lat + (b.lat - a.lat) * frac
        lon = a.lon + (b.lon - a.lon) * frac
        heading = a.heading if a.heading is not None else bearing_deg(
            a.lat, a.lon, b.lat, b.lon
        )
        return {"lat": lat, "lon": lon, "heading": heading}

    return lookup


def dedupe_by_location(records: list, radius_m: float = 8.0) -> list:
    """Merge same-class records whose locations are within radius_m.

    Keeps the highest-confidence record of each cluster and drops the rest --
    the same physical defect seen twice (repeated pass, or a broken track)
    collapses to one. Records without a location are passed through untouched.
    """
    kept, dropped = [], set()
    for i, r in enumerate(records):
        if i in dropped or not getattr(r, "location", None):
            if not getattr(r, "location", None):
                kept.append(r)
            continue
        cluster = [r]
        for j in range(i + 1, len(records)):
            o = records[j]
            if j in dropped or o.cls_name != r.cls_name or not getattr(o, "location", None):
                continue
            d = haversine_m(
                r.location["lat"], r.location["lon"],
                o.location["lat"], o.location["lon"],
            )
            if d <= radius_m:
                cluster.append(o)
                dropped.add(j)
        kept.append(max(cluster, key=lambda x: x.conf))
    return kept


def records_to_geojson(records: list) -> dict:
    """FeatureCollection of Point features, one per located defect record."""
    features = []
    for r in records:
        loc = getattr(r, "location", None)
        if not loc:
            continue
        props = {
            "track_id": r.track_id,
            "class": r.cls_name,
            "confidence": round(r.conf, 3),
            "heading_deg": loc.get("heading"),
        }
        if getattr(r, "dimensions", None):
            props.update(r.dimensions)
        if getattr(r, "crop_path", None):
            props["crop"] = r.crop_path
        features.append({
            "type": "Feature",
            "geometry": {"type": "Point", "coordinates": [loc["lon"], loc["lat"]]},
            "properties": props,
        })
    return {"type": "FeatureCollection", "features": features}


def write_geojson(records: list, out_path: str) -> int:
    """Write located records to a GeoJSON file; return the feature count."""
    fc = records_to_geojson(records)
    Path(out_path).write_text(json.dumps(fc, indent=2))
    return len(fc["features"])
