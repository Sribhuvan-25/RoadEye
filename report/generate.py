"""Generate an inspection report from a session's defects.json.

Ties the module together: load defects -> build the precomputed payload ->
call the LLM with the versioned system prompt -> validate the result ->
regenerate once on failure -> write report.md. This is the prompt-development
harness; the Swift app will mirror this flow once the prompt is stable.

Usage:
    export OPENROUTER_API_KEY=sk-or-...
    python -m report.generate --defects report/fixtures/session_demo.json \
        --session demo-001 --out report/out/demo-001.md

    # Build and inspect the payload without calling the LLM (free, offline):
    python -m report.generate --defects report/fixtures/session_demo.json \
        --session demo-001 --dry-run
"""
import argparse
import json
from pathlib import Path

from report import openrouter, payload as payload_mod, validator

PROMPT_PATH = Path(__file__).parent / "system_prompt.md"


def system_prompt() -> str:
    return PROMPT_PATH.read_text()


def generate(
    defects_path: str,
    session_id: str,
    model: str = openrouter.DEFAULT_MODEL,
    duration_s: float = None,
    started_epoch: float = None,
    max_attempts: int = 2,
) -> tuple:
    """Return (report_text, payload, problems). problems empty = validated."""
    defects = payload_mod.load_defects(defects_path)
    payload = payload_mod.build_payload(
        defects, session_id, started_epoch=started_epoch, duration_s=duration_s
    )
    user_content = json.dumps(payload, indent=2)
    sys_prompt = system_prompt()

    report_text, problems = "", ["not attempted"]
    for attempt in range(1, max_attempts + 1):
        report_text = openrouter.complete(sys_prompt, user_content, model=model)
        problems = validator.validate(report_text, payload)
        if not problems:
            break
        print(f"attempt {attempt}: {len(problems)} validation problem(s):")
        for p in problems:
            print(f"  - {p}")
        if attempt < max_attempts:
            print("regenerating...")

    return report_text, payload, problems


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--defects", required=True, help="path to defects.json")
    ap.add_argument("--session", required=True, help="session id for the report")
    ap.add_argument("--model", default=openrouter.DEFAULT_MODEL)
    ap.add_argument("--duration-s", type=float, default=None)
    ap.add_argument("--out", default=None, help="write report here (default: stdout)")
    ap.add_argument("--dry-run", action="store_true",
                    help="build and print the payload only; no LLM call")
    args = ap.parse_args()

    if args.dry_run:
        defects = payload_mod.load_defects(args.defects)
        p = payload_mod.build_payload(defects, args.session, duration_s=args.duration_s)
        print(json.dumps(p, indent=2))
        return

    report_text, _, problems = generate(
        args.defects, args.session, model=args.model, duration_s=args.duration_s
    )

    if problems:
        print(f"\nWARNING: report still has {len(problems)} problem(s) after retries.")

    if args.out:
        Path(args.out).parent.mkdir(parents=True, exist_ok=True)
        Path(args.out).write_text(report_text)
        print(f"Wrote {args.out}")
    else:
        print("\n" + report_text)


if __name__ == "__main__":
    main()
