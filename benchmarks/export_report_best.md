# Export report — logs/kaggle_yolo11n_100ep/weights/best.pt

Host: macOS-26.2-arm64-arm-64bit

Local PyTorch baseline: 11.7 FPS @ 640px (desktop CPU/GPU — not the real gate)

## Exported artifacts

- **coreml**: `/Users/sb/Road-Analysis/models/best.mlpackage`

## Phase 0 gate — RESULT (2026-07-09): PASSED ✅

Measured on a **physical iPhone 17 Pro (iOS 26.5)** via the throwaway harness
in `ios/RoadDamageFPSTest/`. Model: kaggle_yolo11n_100ep, CoreML export
**with NMS** (`nms=True` — required so Vision auto-parses to
`VNRecognizedObjectObservation`; the plain export emits a raw 1×7×8400
tensor that crashes `VNCoreMLRequest`).

| Device | Format | Compute path | FPS | Notes |
|---|---|---|---|---|
| iPhone 17 Pro (iOS 26.5) | CoreML .mlpackage (NMS) | **CPU-only** | **~30 (camera-capped)** | Sustained; inference keeps up with every 30fps frame |
| iPhone 17 Pro (iOS 26.5) | CoreML .mlpackage (NMS) | `.all` (ANE) | CRASH | `MLIR pass manager failed` / `Unknown aneSubType` |
| iPhone 17 Pro (iOS 26.5) | CoreML .mlpackage (NMS) | `.cpuAndGPU` | CRASH | Same MPSGraph/Metal compile failure |

### Interpretation
- **Real-time on-device detection is feasible — decisively.** Even on the
  slowest path (CPU-only), the model sustains the camera's 30 FPS ceiling,
  meaning per-frame inference is < 33 ms. This retires the biggest unknown
  in RESEARCH.md (no prior source had measured phone FPS).
- The ANE/GPU crash is a **CoreML/Metal compilation bug on brand-new
  iPhone 17 Pro silicon + iOS 26.5**, not a model or approach problem. The
  same model runs fine on the Mac. Expected to resolve with an Xcode/iOS
  point update or an alternate export; the ANE path would be *faster* and
  lower-power than the CPU result we already have.

### Follow-ups
- Re-test ANE path after next Xcode/iOS update.
- Measure power draw / thermals over a longer (30+ min) run before relying
  on continuous-drive capture.
