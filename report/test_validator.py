"""Self-test for the validator: a faithful report passes, a tampered one fails.

Uses the demo fixture's payload so the number set is real. No LLM call.
"""
import json
from pathlib import Path

from report import payload as payload_mod, validator

FIX = Path(__file__).parent / "fixtures" / "session_demo.json"

GOOD = """# Road Inspection Report
Session demo-001, 32.0 seconds surveyed.

## Summary
6 defects found; 2 severe (Crack, Pothole) need attention first.

## Defects
**#7 Crack — severe** — 0.18x3.4 m (0.61 m2) at 37.422105, -122.08376 — schedule repair.
**#3 Pothole — severe** — 0.62x0.58 m (0.36 m2) at 37.421998, -122.084 — schedule repair.
**#11 Crack — moderate** — 0.12x1.6 m (0.19 m2) at 37.42214, -122.0837 — monitor.
**#9 Manhole — low** — 0.64x0.63 m (0.4 m2) at 37.42208, -122.08382 — informational only.
**#5 Pothole — low** — 0.28x0.24 m (0.07 m2) at 37.42204, -122.08388 — log only.
**#14 Pothole — low** — not measured at no GPS fix — log only.

## Notes
Dimensions are IPM-estimated pending field validation; 1 defect unmeasured; 1 defect has no GPS fix.
"""

BAD = GOOD.replace("0.61 m2", "9.99 m2") + \
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
