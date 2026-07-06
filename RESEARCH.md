# Road Damage Detection MVP — Landscape Research

*Compiled 2026-07-06 from a multi-agent deep-research pass: 24 sources fetched, 117 claims extracted, top 25 adversarially fact-checked (23 confirmed, 2 refuted). Confidence labels reflect that verification.*

## Scope

Target system: real-time, on-device detection of road surface damage (potholes; longitudinal / transverse / alligator cracks; rutting; patches) from a vehicle-mounted camera with GPS/IMU, with geotagging and physical dimension estimates (length / width / area, ideally depth). MVP for evaluation by a company for pavement inspection.

---

## Verified findings

### 1. Dataset: RDD2022 is the foundation — and it's commercially usable

- **47,420 road images, 55,000+ annotated damage instances, six countries** (Japan, India, Czech Republic, Norway, US, China). The standard benchmark; its successor challenge (ORDDC 2024) reused it. *(high confidence, 8 claims unanimous)*
- **License: CC BY 4.0** — commercial use permitted with attribution. DOI 10.6084/m9.figshare.21431547.v1. Caveat: the US subset derives from Google Street View imagery, which may carry separate provenance considerations.
- **Four evaluated classes**: longitudinal cracks (D00), transverse cracks (D10), alligator cracks (D20), potholes (D40) — each with >5,500 labels. **Rutting is not covered**; patches/repairs exist only as auxiliary labels in some country subsets. Our full taxonomy needs supplemental data.
- Only ~38k training images have public annotations (test labels withheld).
- Complementary sets: **UDTIRI** (1,000 vehicle-captured pothole images, pixel/instance labels), **UDTIRI-Crack** (2,500 pixel-labeled crack images, 5 crack types), **PothRGBD** (~1,000 RGB+depth pothole images from RealSense D415, on GitHub/Kaggle), CRACK500, Pothole-600 (RGB + stereo disparity).

### 2. Accuracy ceiling: F1 ≈ 0.77, and real-time costs ~10 points

- CRDDC 2022 winner: **F1 0.7699** on the six-country test set, using an *ensemble* of YOLO + Faster R-CNN models. Runners-up: YOLOv5x ensemble (0.743), YOLOv7 (0.741). **10 of the top 11 teams used YOLO variants.** *(high confidence)*
- ORDDC 2024, same data but under real-time constraints: best **F1 ≈ 0.67**. Expect a single real-time edge model to land in the 0.6–0.7 F1 range, not 0.77. Set the company's expectations accordingly.

### 3. Model choice: YOLO family, nano/small size

- **YOLO26** (late 2025) is the most deployment-friendly current option: NMS-free end-to-end predictions (lower edge latency/complexity), native export to **TensorRT, ONNX, CoreML, TFLite, OpenVINO** — covering both Jetson and smartphone paths. YOLO26n: 40.9 mAP50-95 COCO, 38.9 ms CPU ONNX, 1.7 ms T4 TensorRT. *(high confidence, but vendor-reported figures)*
- Sub-5-GFLOP road-damage detectors can lead benchmarks: **RT-DSAFDet** (1.8M params, 4.6 GFLOPs) beats YOLOv8-m/YOLOv10-m by 5.8–12.6 mAP50 on UAV-PDD2023, code public, peer-reviewed. (UAV imagery, so architectural evidence, not a drop-in.)
- **⚠️ No verified FPS numbers exist on actual edge hardware** (Jetson / smartphone) — every published speed figure that survived fact-checking was measured on A100/T4/RTX-3090/Xeon. Edge throughput must be benchmarked empirically, early.

### 4. Detection vs. segmentation

- Full semantic segmentation is not edge-viable for the MVP: the best UDTIRI segmentation model (Segmenter, 80.74% IoU) runs at **9.5 FPS on a desktop GPU**. *(medium confidence)*
- But **lightweight instance segmentation is feasible**: an enhanced YOLOv8n-seg (4.1M params, 13.2 GFLOPs) hit **93.8% mAP@50 pothole segmentation at 110 FPS on desktop**. Masks (not boxes) are what enable area measurement. *(high confidence; preprint, authors' own dataset)*
- Practical implication: **boxes for cracks (detection), masks for potholes (segmentation)** — or a small -seg model for everything.

### 5. Dimension estimation — the highest-risk component

- The **only measurement-accuracy result that survived fact-checking uses an active RGB-D sensor**: segmentation masks + RealSense D415 depth → pothole perimeter ±2.3 cm, depth ±0.24 cm — but evaluated on just **five images**. *(medium confidence)*
- **Every claim about monocular measurement accuracy (IPM, Depth Anything/MiDaS, SfM, GPS/IMU-scaled) failed adversarial verification.** This is an evidence gap, not proof it can't work — a promising unverified lead is arXiv 2505.21049 (ACSH-YOLOv8 + BoT-SORT tracking + Depth Anything V2 metric depth + Kalman smoothing for pothole area from vehicle video), which is almost exactly our pipeline and should be read closely.
- Conclusion: plan to **validate measurement accuracy ourselves with ground truth** (tape-measured defects). Length/width/area via calibrated inverse perspective mapping is geometrically sound for a flat road plane; pothole *depth* from monocular video is unproven — treat depth as a stretch goal or an RGB-D hardware upgrade path.

---

## What the research could NOT verify (gaps to close ourselves)

1. **Edge FPS**: no measured Jetson/smartphone throughput for any modern road-damage model → benchmark in Phase 0/1.
2. **Monocular measurement accuracy** → own field validation (Phase 3).
3. **Commercial landscape**: no claims about vialytics, Vaisala RoadAI, Michelin/RoadBotics survived verification. Search-level (unverified) picture: vialytics is the closest comp — windshield-mounted smartphone, photo every ~10 ft, ~15 damage classes, GIS/work-order backend. Worth a manual competitive scan before the company pitch.
4. **Tracking/dedup engineering**: no verified sources on cross-frame dedup; standard practice (unverified) is ByteTrack/BoT-SORT + GPS clustering.

## Refuted claims (excluded)

- "RDD2022 contains no patch labels at all" — false; some country subsets carry repair/patch auxiliary labels.
- "YOLOv6 is UDTIRI's top detector at 69.6% AP / 48.7 FPS" — did not check out against the paper.

## Key sources

- RDD2022 dataset paper — arxiv.org/abs/2209.08538 (data: figshare DOI 10.6084/m9.figshare.21431547.v1)
- CRDDC 2022 challenge results — arxiv.org/abs/2211.11362
- Real-time road damage detection survey (J. Real-Time Image Processing, 2025) — doi.org/10.1007/s11554-025-01683-1
- Enhanced YOLOv8n-seg + PothRGBD dataset + RGB-D measurement — arxiv.org/pdf/2505.04207 (data: github.com/ymyurdakul/PData)
- RT-DSAFDet — arxiv.org/pdf/2409.02546 (code: github.com/JEFfersusu/RT-DSAFDet)
- UDTIRI benchmark — arxiv.org/html/2304.08842v3 (udtiri.com/benchmarks)
- YOLO26 — docs.ultralytics.com/models/yolo26 · arxiv.org/html/2509.25164v5
- Video pothole area estimation (unverified lead, read first) — arxiv.org/abs/2505.21049
- Reference implementations: github.com/sekilab/RoadDamageDetector · github.com/TrongDuyNguyen0611/Road-Damage-Detection-Tflite
