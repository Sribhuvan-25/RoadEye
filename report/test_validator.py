"""Self-test for the validator: a faithful report passes, a tampered one fails.

Uses the demo fixture's payload so the number set is real. No LLM call.
"""
import json
from pathlib import Path

from report import payload as payload_mod, validator

FIX = Path(__file__).parent / "fixtures" / "session_demo.json"

GOOD = """# Road Inspection Report
Session demo-001, 32.0 seconds surveyed.

## Executive Summary
6 defects were detected: 2 severe, 1 moderate, 3 low. The two severe defects
(one crack, one pothole) are the priority.

## Severity Overview
| Severity | Count | Classes present |
|---|---|---|
| severe | 2 | Crack, Pothole |
| moderate | 1 | Crack |
| low | 3 | Manhole, Pothole |

## Defects
**Defect #7 — Crack — severe** Size: 0.18 x 3.4 m, area 0.61 m2. Confidence 51.4%.
**Defect #3 — Pothole — severe** Size 0.62 x 0.58 m, area 0.36 m2. Confidence 84.2%.
**Defect #11 — Crack — moderate** Size 0.12 x 1.6 m, area 0.19 m2. Confidence 40.2%.
**Defect #9 — Manhole — low** Size 0.64 x 0.63 m, area 0.4 m2. Confidence 91%.
**Defect #5 — Pothole — low** Size 0.28 x 0.24 m, area 0.07 m2. Confidence 67.3%.
**Defect #14 — Pothole — low** Not measured. Location not recorded. Confidence 58.8%.

## Recommended Actions
Severe (2): schedule repair. Moderate (1): maintenance queue. Low (3): log only.

## Limitations and Data Caveats
Dimensions via IPM, pending field validation. 1 defect unmeasured, 1 unlocated.
"""

BAD = GOOD.replace("area 0.61 m2", "area 9.99 m2") + \
    "\nEstimated repair cost: 4200 dollars.\n"

MISSING = "\n".join(
    ln for ln in GOOD.splitlines() if "#14" not in ln
)


def main():
    defects = payload_mod.load_defects(str(FIX))
    payload = payload_mod.build_payload(defects, "demo-001", duration_s=32.0)

    good_problems = validator.validate(GOOD, payload)
    print(f"GOOD report: {len(good_problems)} problem(s)")
    for p in good_problems:
        print("  -", p)

    bad_problems = validator.validate(BAD, payload)
    print(f"\nBAD report (invented number + cost): {len(bad_problems)} problem(s)")
    for p in bad_problems:
        print("  -", p)

    missing_problems = validator.validate(MISSING, payload)
    print(f"\nMISSING report (dropped #14): {len(missing_problems)} problem(s)")
    for p in missing_problems:
        print("  -", p)

    ok = (not good_problems) and bad_problems and missing_problems
    print("\nPASS" if ok else "\nFAIL: validator did not behave as expected")


if __name__ == "__main__":
    main()
