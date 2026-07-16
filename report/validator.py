"""Structural check that a generated report is faithful to its payload.

Catches the two hallucination modes a prompt alone can't guarantee against:
a defect dropped from the report, and a number that isn't in the input. Cheap
regex + set comparison -- not a grader of prose quality, just a fact gate.
Returns a list of problems; empty list means the report passed.
"""
import re

REQUIRED_HEADINGS = [
    "# Road Inspection Report",
    "## Executive Summary",
    "## Severity Overview",
    "## Defects",
    "## Recommended Actions",
    "## Limitations and Data Caveats",
]

_NUM_RE = re.compile(r"(?<![\w.])-?\d+\.?\d*")


def _numbers_in(text: str) -> set:
    """Set of numeric tokens in text, normalized to float then back to a key."""
    out = set()
    for m in _NUM_RE.findall(text):
        try:
            out.add(_num_key(float(m)))
        except ValueError:
            continue
    return out


def _num_key(v: float) -> str:
    """Normalize a number so 0.60, 0.6, and 0.600 compare equal."""
    if v == int(v):
        return str(int(v))
    return f"{v:.6f}".rstrip("0")


def _allowed_numbers(payload: dict) -> set:
    """Every numeric value legitimately derivable from the payload.

    Includes raw fields plus the presentation forms the prompt asks for:
    confidence as a percentage, and integer counts. A report number outside
    this set is treated as invented.
    """
    allowed = set()

    def add(v):
        if isinstance(v, bool) or v is None:
            return
        if isinstance(v, (int, float)):
            allowed.add(_num_key(float(v)))

    s = payload["session"]
    for v in (s.get("defect_count"), s.get("duration_s"), s.get("started_epoch")):
        add(v)

    c = payload["counts"]
    for v in c["by_class"].values():
        add(v)
    for v in c["by_severity"].values():
        add(v)
    add(c.get("total_measured_area_m2"))

    dq = payload["data_quality"]
    add(dq.get("unmeasured_count"))
    add(dq.get("unlocated_count"))

    for r in payload["defects"]:
        add(r.get("id"))
        add(r.get("n_frames"))
        conf = r.get("confidence")
        add(conf)
        if isinstance(conf, (int, float)):
            add(round(conf * 100, 1))
            add(round(conf * 100))
        dims = r.get("dimensions") or {}
        for v in dims.values():
            add(v)
        loc = r.get("location") or {}
        for v in loc.values():
            add(v)

    for i in range(0, 101):
        allowed.add(str(i))

    return allowed


def validate(report: str, payload: dict) -> list:
    """Return a list of human-readable problems; empty = passed."""
    problems = []

    for h in REQUIRED_HEADINGS:
        if h not in report:
            problems.append(f"missing required heading: {h!r}")

    for r in payload["defects"]:
        did = r.get("id")
        if did is None:
            continue
        if not re.search(rf"#\s*{re.escape(str(did))}\b", report):
            problems.append(f"defect id {did} not referenced in report")

    n_blocks = len(re.findall(r"\*\*Defect\s*#", report))
    want = payload["session"].get("defect_count", 0)
    if want and n_blocks != want:
        problems.append(
            f"found {n_blocks} defect blocks, expected {want}"
        )

    allowed = _allowed_numbers(payload)
    for tok in _numbers_in(report):
        if tok not in allowed:
            problems.append(f"number {tok} in report is not in the input data")

    return problems
