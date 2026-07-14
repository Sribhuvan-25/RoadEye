# iOS — RoadEye app

Fully on-device MVP: the phone runs the entire pipeline and saves a browsable
per-drive archive — no backend, works offline. Drive, park, review what was
found (defect crop + location + measured size) under "Past Sessions".

Pipeline (all on-device, ported from the validated `pipeline/` Python):
- `CameraFPSController` — camera + live CoreML inference; feeds detections to
  the collector while recording
- `SimpleTracker` — IoU tracker giving detections stable IDs across frames
  (Vision has no cross-frame identity; ByteTrack did this in Python)
- `DetectionCollector` — accumulates tracked detections + best crop per track
- `Geometry` — inverse perspective mapping (FOV intrinsics + horizon pitch);
  numerically matches `pipeline/dimension_estimation.py`
- `SessionProcessor` — group→dedup→geotag→measure into `DefectRecord`s
- `SessionStore` — persists crops + defects.json per session
- `LocationRecorder` — CoreLocation GPS log
- `SessionsView` / `SessionDetailView` — the review UI

Started as the Phase 0 FPS harness (confirmed ~30 FPS on iPhone 17 Pro; see
`../benchmarks/export_report_best.md`).

## Model (not committed)

`RoadDamageFPSTest/Models/RoadDamageDetector.mlpackage` is a gitignored binary.
Regenerate before building:

```bash
python scripts/export_and_benchmark.py --model models/best.pt --formats coreml
cp -r models/best.mlpackage \
    ios/RoadDamageFPSTest/RoadDamageFPSTest/Models/RoadDamageDetector.mlpackage
```

Export **with NMS** so Vision parses the output as `VNRecognizedObjectObservation`.
Run on a physical device (the Simulator has no camera). The project uses Xcode
16 synchronized groups, so new source files are picked up automatically.

## Measurement config

Set via the in-app Settings screen (gear icon), persisted in `AppSettings`:
- **Mount height** — road surface to camera; scales every dimension.
- **Horizon line** — drag a line onto the real horizon over the live feed to
  set camera pitch.

These drive the IPM measurement. Accuracy still needs field validation (a
drive + tape-measured defects).
