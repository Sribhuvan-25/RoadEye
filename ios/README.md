# iOS — Phase 0 FPS harness

Throwaway app used to confirm the detector runs in real time on a physical
iPhone. It shows a live camera feed with an on-screen FPS counter and
per-frame detection count. Not a production app.

## Model (not committed)

`RoadDamageFPSTest/Models/RoadDamageDetector.mlpackage` is a gitignored
binary. Regenerate and add it before building:

```bash
python scripts/export_and_benchmark.py --model models/best.pt --formats coreml
cp -r models/best.mlpackage \
    ios/RoadDamageFPSTest/RoadDamageFPSTest/Models/RoadDamageDetector.mlpackage
```

Export **with NMS** so Vision parses the output as `VNRecognizedObjectObservation`.
Then in Xcode: add the `.mlpackage` to the target, and run on a physical device
(the Simulator has no camera).

## Result

Sustained ~30 FPS (camera-capped) on iPhone 17 Pro, CPU-only. See
`../benchmarks/export_report_best.md` for the full measurement and the
known ANE/GPU compile issue on iOS 26.5.
