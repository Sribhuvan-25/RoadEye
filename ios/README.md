# iOS — RoadEye capture app

Thin capture app (hybrid architecture): the phone records a drive, the Python
backend does the heavy processing. Per session it captures video + live
on-device detection + a GPS log, then exports the session for the backend to
process into geotagged, measured defects.

Files:
- `CameraFPSController` — camera + live CoreML inference + video recording
- `LocationRecorder` — CoreLocation GPS log (writes the CSV `pipeline/geo.py` reads)
- `SessionRecorder` — coordinates video + GPS on a shared clock; writes a
  `session_<ts>/` folder (video.mov + gps.csv) to Documents
- `ContentView` — record/stop + share-sheet export UI

Started as the Phase 0 FPS harness (which confirmed ~30 FPS on iPhone 17 Pro;
see `../benchmarks/export_report_best.md`).

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
