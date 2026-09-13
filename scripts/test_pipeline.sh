#!/bin/bash
# Regression tests for the on-device capture pipeline (geometry + session
# processing), compiled from the app's own sources and run on the Mac.
set -euo pipefail
SRC=ios/RoadDamageFPSTest/RoadDamageFPSTest
OUT=$(mktemp -d); trap 'rm -rf "$OUT"' EXIT
swiftc -o "$OUT/run" \
    "$SRC/Pipeline/DefectModels.swift" \
    "$SRC/Pipeline/Geometry.swift" \
    "$SRC/Pipeline/SessionProcessor.swift" \
    scripts/pipeline_harness/main.swift
"$OUT/run"
