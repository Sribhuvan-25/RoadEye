"""Deterministic severity scoring for defect records.

The LLM never decides severity -- it only narrates what this module computes.
Given a defect's class and measured size, return a fixed severity level plus
the reason, so the same defect always scores the same way, run to run.

Thresholds are first-pass engineering estimates for a demo, NOT adopted from a
published pavement standard (e.g. ASTM D6433 PCI). They are the single place to
tune when field data arrives -- change them here and every report updates.
"""
from typing import Optional

LEVELS = ["low", "moderate", "severe"]
LEVEL_RANK = {name: i for i, name in enumerate(LEVELS)}

POTHOLE_AREA_BOUNDS = [("severe", 0.30), ("moderate", 0.10), ("low", 0.0)]
CRACK_LENGTH_BOUNDS = [("severe", 3.0), ("moderate", 1.0), ("low", 0.0)]


def _class_key(cls_name: str) -> str:
    """Normalize a class label to a lowercase key (Pothole/pothole/POTHOLE)."""
    return (cls_name or "").strip().lower()


def score(cls_name: str, dimensions: Optional[dict]) -> dict:
    """Return {'level', 'metric', 'metric_value', 'reason'} for one defect.

    dimensions is the record's measured size dict (width_m/length_m/area_m2)
    or None when the defect was never measured (no camera config). Unmeasured
    defects can't be sized, so they score 'low' with an explicit reason -- the
    report then flags them as needing manual assessment rather than silently
    downgrading a possibly-serious defect.
    """
    key = _class_key(cls_name)

    if dimensions is None:
        return {
            "level": "low",
            "metric": None,
            "metric_value": None,
            "reason": "not measured (no camera configuration); severity unassessed",
        }

    if key == "manhole":
        return {
            "level": "low",
            "metric": None,
            "metric_value": None,
            "reason": "manhole cover -- infrastructure, not pavement damage",
        }

    if key == "pothole":
        area = dimensions.get("area_m2")
        if area is None:
            return _unsized("pothole", "area")
        level = _bound_level(area, POTHOLE_AREA_BOUNDS)
        return {
            "level": level,
            "metric": "area_m2",
            "metric_value": area,
            "reason": f"pothole area {area:.2f} m²",
        }

    if key == "crack":
        length = dimensions.get("length_m")
        if length is None:
            return _unsized("crack", "length")
        level = _bound_level(length, CRACK_LENGTH_BOUNDS)
        return {
            "level": level,
            "metric": "length_m",
            "metric_value": length,
            "reason": f"crack length {length:.2f} m",
        }

    return {
        "level": "low",
        "metric": None,
        "metric_value": None,
        "reason": f"unrecognized class '{cls_name}'; severity unassessed",
    }


def _bound_level(value: float, bounds: list) -> str:
    """First (level, lower_bound) whose bound value meets or exceeds -> level."""
    for level, lower in bounds:
        if value >= lower:
            return level
    return "low"


def _unsized(cls_name: str, metric: str) -> dict:
    return {
        "level": "low",
        "metric": None,
        "metric_value": None,
        "reason": f"{cls_name} missing {metric}; severity unassessed",
    }


if __name__ == "__main__":
    cases = [
        ("Pothole", {"area_m2": 0.35}, "severe"),
        ("Pothole", {"area_m2": 0.30}, "severe"),
        ("Pothole", {"area_m2": 0.29}, "moderate"),
        ("Pothole", {"area_m2": 0.10}, "moderate"),
        ("Pothole", {"area_m2": 0.05}, "low"),
        ("Crack", {"length_m": 4.0}, "severe"),
        ("Crack", {"length_m": 3.0}, "severe"),
        ("Crack", {"length_m": 2.9}, "moderate"),
        ("Crack", {"length_m": 1.0}, "moderate"),
        ("Crack", {"length_m": 0.5}, "low"),
        ("Manhole", {"area_m2": 5.0}, "low"),
        ("Pothole", None, "low"),
        ("Gremlin", {"area_m2": 9.9}, "low"),
    ]
    ok = True
    for cls, dims, want in cases:
        got = score(cls, dims)["level"]
        mark = "OK " if got == want else "FAIL"
        if got != want:
            ok = False
        print(f"{mark} {cls:8} {str(dims):24} -> {got:8} (want {want})")
    print("\nAll passed." if ok else "\nFAILURES above.")
