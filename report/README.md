# report — LLM inspection report

Turns a session's `defects.json` into a written pavement-inspection report via
one OpenRouter call. This is the **one cloud step** in an otherwise on-device
pipeline (LLMs don't run on-device); detection and measurement stay local.

## Design rule: the LLM narrates, it does not decide

Everything numerical or classifiable is computed in code *before* the call, so
the model has nothing to invent and the same session always reports the same
way:

- **`severity.py`** — deterministic severity (low/moderate/severe) from class +
  measured size. The one place to tune thresholds when field data arrives.
- **`payload.py`** — loads `defects.json` (tolerant of both the Python
  pipeline's snake_case and the Swift app's camelCase), attaches severity,
  precomputes all counts and orderings, flags unmeasured/unlocated defects.
- **`system_prompt.md`** — the versioned prompt: role, hard data rules, the
  fixed report template, the severity→action mapping, and the mandated
  limitations section. Iterate on report quality here.
- **`openrouter.py`** — stdlib-only OpenRouter client; key from
  `OPENROUTER_API_KEY`, model is a config value (default
  `anthropic/claude-sonnet-4.5`), temperature 0.
- **`validator.py`** — structural fact-check: all headings present, every
  defect id referenced, defect-block count matches, and **no number appears
  that isn't in the payload**. Generation retries once on failure.
- **`generate.py`** — the harness that runs the whole flow.

## Use

```bash
# Offline: build and inspect the payload the LLM would see (free, no key).
python -m report.generate --defects report/fixtures/session_demo.json \
    --session demo-001 --duration-s 32 --dry-run

# Full report (needs a key).
export OPENROUTER_API_KEY=sk-or-...
python -m report.generate --defects report/fixtures/session_demo.json \
    --session demo-001 --duration-s 32 --out report/out/demo-001.md

# Try a different model without code changes:
python -m report.generate ... --model openai/gpt-4o
```

## Tests (no key needed)

```bash
python report/severity.py         # severity thresholds + every branch
python -m report.test_validator   # faithful report passes; tampered fails
```

## Next: Swift integration

Once the prompt is stable, the app mirrors this flow — a "Generate Report"
button on a saved session posts the same payload + prompt to OpenRouter, saves
`report.md` into the session folder, and shows it in-app. The key lives in the
iOS Keychain (entered in Settings), not in code.
