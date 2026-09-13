# iOS — RoadEye app

Fully on-device MVP: the phone runs the entire pipeline and saves a browsable
per-drive archive — no backend, works offline. Drive, park, review what was
found (defect crop + location + measured size) under "Past Sessions".

Source layout (`RoadDamageFPSTest/`):
- `Capture/` — `CameraFPSController` (camera + live CoreML inference),
  `CameraPreviewView`, `DetectionCollector` (tracked detections + best crops)
- `Pipeline/` — on-device processing ported from the validated `pipeline/`
  Python: `Geometry` (IPM, numerically matches `dimension_estimation.py`),
  `SimpleTracker` (IoU cross-frame IDs), `SessionProcessor`
  (group→dedup→geotag→measure), `DefectModels`
- `Session/` — `SessionRecorder`, `SessionStore` (crops + defects.json),
  `LocationRecorder` (CoreLocation GPS)
- `Report/` — `OfflineReport` (deterministic, on-device), `ReportGenerator` +
  `OpenRouterClient` (optional AI-written version), `ReportValidator`,
  `Severity`, `KeychainStore` (API key)
- `Views/` — `ContentView`, `DetectionOverlay` (live boxes), `SessionsView`,
  `DefectPhotoView` (full-screen crop), `ReportView`, `SettingsView`
- `Settings/` — `AppSettings` (persisted measurement config)
- `App/` — app entry point · `Models/` — CoreML model (gitignored)

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

**Defects near the horizon are reported without a size.** The ground
projection is numerically unstable there — a pixel one row below the horizon
maps hundreds of metres out — so measurements beyond 30 m, or implying a
single defect larger than 12 m², are rejected rather than reported. Getting
the horizon line right is what keeps defects measurable.

## Reports

Every session can produce an inspection report two ways:
- **Build Report** — deterministic, on-device, no key and no network.
- **Write with AI** — same facts, nicer prose, via OpenRouter. Needs an API
  key saved in Settings (stored in the Keychain, never in code).

Both are validated against the session payload so no number appears that
isn't in the data. Sessions also export to GeoJSON + CSV from the detail
screen's ⋯ menu.

## Tests

Run on the Mac, no device needed:

```bash
./scripts/test_pipeline.sh      # geometry + session processing regressions
./scripts/test_swift_report.sh  # Swift/Python report parity, validator, keychain
```
