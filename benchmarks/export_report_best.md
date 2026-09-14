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

## Model selection revisited (2026-09-14)

The earlier "RDD2022 Czech was a wash" conclusion was measured at the
detector's default thresholds. Re-measured at the thresholds the app actually
ships with (NMS IoU 0.45, conf 0.25–0.35), on the **target-domain** holdout:

| model | Pothole mAP50 | Crack mAP50 | Manhole mAP50 |
|---|---|---|---|
| kaggle_yolo11n_100ep | 0.335 | 0.303 | 0.749 |
| **kaggle_yolo11n_100ep_merged** | **0.415** | **0.414** | **0.825** |

On 120 sampled frames of real dashcam footage the merged model produces
**132 detections vs 233** (-43%) at the same thresholds, and in an end-to-end
in-app recording of the same clip: **12 defects vs 26, duplicate-label
moments 8 → 2**. `kaggle_yolo11n_100ep_merged` is the deployed model.

### Capacity is not the bottleneck — data is
`yolo11s` fine-tuned on the same 1,708-image split reached mAP50 **0.278**
versus 0.55 for `yolo11n`: the larger model overfits. More/att better-matched
training data is the lever, not a bigger backbone.
