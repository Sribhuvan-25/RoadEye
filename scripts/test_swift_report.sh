#!/bin/bash
# Verifies the Swift report port against the canonical Python implementation:
#   1. compile the app's Report/ sources + macOS harness
#   2. payload parity: Swift builder output == Python builder output (semantic)
#   3. prompt sync: embedded ReportPrompt.text == report/system_prompt.md
#   4. validator behavior: faithful passes, tampered/missing fail
#   5. (--live) real OpenRouter call through the Swift pipeline, validated
# Run from the repo root. Steps 1-4 are offline and free.
set -euo pipefail

SRC=ios/RoadDamageFPSTest/RoadDamageFPSTest
FIXTURE=report/fixtures/session_swift.json
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT

echo "[1/5] compile"
swiftc -o "$OUT/harness" \
    "$SRC/Pipeline/DefectModels.swift" \
    "$SRC/Report/Severity.swift" \
    "$SRC/Report/ReportPayload.swift" \
    "$SRC/Report/ReportPrompt.swift" \
    "$SRC/Report/ReportValidator.swift" \
    "$SRC/Report/OpenRouterClient.swift" \
    "$SRC/Report/ReportGenerator.swift" \
    scripts/report_harness/main.swift

echo "[2/5] payload parity vs Python"
"$OUT/harness" payload "$FIXTURE" swift-001 45.5 > "$OUT/swift_payload.json"
python -m report.generate --defects "$FIXTURE" --session swift-001 \
    --duration-s 45.5 --dry-run > "$OUT/py_payload.json"
python3 - "$OUT/py_payload.json" "$OUT/swift_payload.json" <<'EOF'
import json, sys
py, sw = (json.load(open(p)) for p in sys.argv[1:3])
def diff(a, b, path=""):
    out = []
    if isinstance(a, dict) and isinstance(b, dict):
        for k in sorted(set(a) | set(b)):
            if k not in a: out.append(f"{path}.{k}: only in swift")
            elif k not in b: out.append(f"{path}.{k}: only in python")
            else: out += diff(a[k], b[k], f"{path}.{k}")
    elif isinstance(a, list) and isinstance(b, list):
        if len(a) != len(b): out.append(f"{path}: len {len(a)} vs {len(b)}")
        else:
            for i, (x, y) in enumerate(zip(a, b)): out += diff(x, y, f"{path}[{i}]")
    elif a != b: out.append(f"{path}: python={a!r} swift={b!r}")
    return out
d = diff(py, sw)
if d:
    print("\n".join(d)); sys.exit(1)
print("      parity OK")
EOF

echo "[3/5] prompt sync"
"$OUT/harness" prompt > "$OUT/swift_prompt.txt"
diff report/system_prompt.md "$OUT/swift_prompt.txt" > /dev/null \
    && echo "      prompt OK" || { echo "PROMPT DRIFT vs system_prompt.md"; exit 1; }

echo "[4/5] validator behavior"
"$OUT/harness" validator-test "$FIXTURE" swift-001 | tail -1

if [[ "${1:-}" == "--live" ]]; then
    echo "[5/5] live OpenRouter generation"
    "$OUT/harness" generate "$FIXTURE" swift-001 45.5 > "$OUT/report.md"
    echo "      live generation validated ($(wc -l < "$OUT/report.md") lines)"
else
    echo "[5/5] skipped (pass --live for a real API call)"
fi

echo "ALL CHECKS PASSED"
