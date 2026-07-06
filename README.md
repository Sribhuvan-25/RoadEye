# Road-Analysis

Real-time, on-device road damage detection + dimension estimation MVP.
Vehicle-mounted camera (+ GPS/IMU) → detect potholes/cracks → geotag →
estimate physical size.

Start here:
- [RESEARCH.md](RESEARCH.md) — landscape review (models, datasets, measurement techniques, gaps)
- [PLAN.md](PLAN.md) — phased build plan and risk register

## Setup

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

## Phase 0 scripts

```bash
# Download RDD2022 dataset (CC BY 4.0)
python scripts/download_rdd2022.py --countries japan india us

# Export a YOLO model to edge formats + get a local speed baseline
python scripts/export_and_benchmark.py --model yolo26n.pt --imgsz 640
```

`export_and_benchmark.py` gives a same-machine comparison only — the real
Phase 0 gate is sideloading the exported `.tflite`/`.mlpackage` onto the
actual target phone and measuring sustained FPS on live camera frames.
Record those results in the generated `benchmarks/export_report_*.md`.

## Layout

```
data/raw/          downloaded datasets (gitignored)
data/processed/     YOLO-format converted annotations (gitignored)
models/             exported model artifacts (gitignored)
scripts/            data download, export/benchmark, training utilities
benchmarks/         export + speed reports
notebooks/          exploratory analysis
logs/               experiment logs
```
