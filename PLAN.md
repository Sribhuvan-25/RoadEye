# Road Damage Detection MVP — Build Plan

*Companion to [RESEARCH.md](RESEARCH.md). Target: real-time, on-device detection + geotagging + dimension estimation from a vehicle-mounted camera with GPS/IMU, packaged as an MVP a company can evaluate.*

## Guiding decisions (from research)

| Decision | Choice | Why |
|---|---|---|
| Detector | YOLO nano/small (start YOLO26n / YOLOv8n-seg) | YOLO dominates every road-damage leaderboard; nano/small is the only size class plausible for real-time edge; native TFLite/CoreML/TensorRT export |
| Task type | Boxes for cracks, masks for potholes | Full segmentation isn't real-time on edge; masks needed only where we measure area |
| Dataset | RDD2022 (CC BY 4.0) + UDTIRI/PothRGBD for potholes | Largest public benchmark, commercially usable; rutting deferred (no public data) |
| Measurement | Inverse perspective mapping (calibrated camera, fixed mount) for length/width/area; depth = stretch goal | Only verified accurate depth result needs RGB-D hardware; monocular depth unproven — validate ourselves |
| Capture device | Smartphone, windshield-mounted (decide vs. Jetson after Phase 0 benchmark) | Matches the dominant commercial form factor (vialytics); GPS/IMU/camera/compute in one box; zero integration hardware |
| Dev strategy | Desktop-first, edge from Phase 4 | Iterate on accuracy with fast tooling; port the frozen pipeline |
| Realistic accuracy target | F1 ≈ 0.6–0.7 on RDD2022 classes in real time | Challenge evidence: 0.77 ensemble ceiling, ~0.67 under real-time constraints |

## MVP definition (what the company sees)

Drive a route with a phone on the windshield → app detects damage live, geotags each defect once (not once per frame), estimates its size → after the drive, a web map shows every defect with class, photo crop, GPS location, and estimated dimensions, exportable as GeoJSON/CSV.

---

## Phase 0 — Feasibility spikes (~1 week)

Kill the two unknowns the literature couldn't answer, before building anything.

1. **Edge FPS benchmark**: export a pretrained YOLO26n and YOLOv8n-seg to TFLite/CoreML (INT8 + FP16), run on the actual target phone (and a Jetson Orin Nano if available). Record FPS at 640px. Gate: ≥10–15 FPS sustained → real-time on-device is viable; below that → fall back to on-device capture + near-real-time processing.
2. **Measurement sanity spike**: mount phone on car, calibrate camera (OpenCV checkerboard), measure mounting height/pitch, implement basic IPM, photograph 5–10 objects of known size on pavement, compare estimated vs. true dimensions. Gate: length/width error under ~15–20% → IPM is the Phase 3 approach.
3. Read arXiv 2505.21049 (video pothole area estimation — closest published pipeline to ours) and skim the CRDDC winner reports.

**Deliverable: go/no-go memo on device + measurement approach.**

## Phase 1 — Detection model (~2–3 weeks)

1. Download RDD2022; convert annotations to YOLO format; train/val split by country subset (hold out the countries closest to deployment geography for validation).
2. Train YOLO26n and YOLOv8n-seg baselines (transfer from COCO weights). Merge pothole masks from UDTIRI/PothRGBD for the segmentation head.
3. Evaluate: per-class F1 at the challenge IoU threshold; compare against the 0.67–0.77 published range. Iterate on augmentation (the #3 challenge team got 0.741 mostly via augmentation, not architecture).
4. Run on recorded dashcam-style video of local roads; qualitatively review false positives (manhole covers, shadows, tar seams are classic confusers).

**Deliverable: trained model + eval report; recorded local test drives.**

## Phase 2 — Video pipeline: tracking, dedup, geotagging (~2 weeks)

1. Frame sampling (process every Nth frame based on Phase 0 FPS budget and vehicle speed).
2. Multi-object tracking across frames (ByteTrack or BoT-SORT) so one physical defect = one track.
3. On track end, emit a single defect record: best frame crop, class, confidence, GPS coordinate (interpolated to detection time), heading from IMU.
4. Spatial dedup for repeated passes (cluster records within ~5–10 m + same class).
5. Output format: GeoJSON per drive session.

**Deliverable: video + GPS log in → deduplicated geotagged defect list out (desktop).**

## Phase 3 — Dimension estimation (~2–3 weeks, highest risk)

1. Camera calibration profile + mount geometry (height, pitch) as per-vehicle config.
2. IPM: project pothole mask / crack box footprint onto the ground plane → length, width, area in cm/m². Kalman-smooth estimates across the frames of a track (per arXiv 2505.21049).
3. **Field validation**: tape-measure ≥20 real defects, drive past them, compare. Report error distribution honestly in the MVP docs — this number is the credibility of the whole product.
4. Stretch: Depth Anything V2 metric depth for pothole depth; validate the same way. If accuracy is poor, document RGB-D (e.g., RealSense-class sensor: verified ±2.3 cm perimeter / ±0.24 cm depth) as the hardware upgrade path rather than shipping bad numbers.

**Deliverable: dimensions on every defect record + measured accuracy report.**

## Phase 4 — Edge deployment (~2–3 weeks)

1. Freeze the pipeline; export model INT8 (TFLite for Android / CoreML for iOS; TensorRT if Jetson won Phase 0).
2. Re-validate accuracy post-quantization (expect small mAP drop; re-check per-class F1).
3. Phone app: camera capture, on-device inference, GPS/IMU logging, live detection overlay, session recording. Tracking/dedup can run on-device or at session upload — decide by Phase 0 FPS headroom.
4. Thermal/battery test: 30+ min continuous drive.

**Deliverable: app that detects live in a moving vehicle.**

## Phase 5 — Reporting backend + demo packaging (~1–2 weeks)

1. Session upload → simple backend (defect store keyed by location).
2. Web map (Leaflet/Mapbox): defects colored by class/severity, click for photo + dimensions; severity bucketing by size (aligns with pavement-index style scoring agencies use).
3. CSV/GeoJSON export; one-page accuracy datasheet (detection F1, measurement error, FPS on device) — the honest numbers are the pitch.
4. Demo script: known route with pre-measured defects.

**Deliverable: end-to-end demo for the company.**

---

## Risk register

| Risk | Mitigation |
|---|---|
| Edge FPS insufficient (unverified in literature) | Phase 0 gate; fall back to capture-now/process-after-drive, still on-device |
| Monocular measurement inaccurate (evidence gap) | Phase 0 spike + Phase 3 field validation; RGB-D documented as upgrade path; never ship unvalidated numbers |
| RDD2022 model doesn't generalize to local roads | Country-held-out validation; fine-tune on a few hundred locally labeled frames if needed |
| Rutting/patches missing from public data | Descope from MVP taxonomy; state as roadmap item |
| Motion blur / night / rain degrade detection | MVP scopes to daylight, dry conditions ≤ ~50 km/h; state limits explicitly |
| Competitive overlap (vialytics et al.) | Manual competitive scan before pitch; differentiate on measurement + openness/price |

## Open questions to resolve along the way

- Actual FPS of YOLO26n / YOLOv8n-seg INT8 on the target phone (Phase 0).
- Achievable monocular measurement error from a moving vehicle (Phase 0/3).
- What vialytics / Vaisala RoadAI / Michelin actually deliver and charge (manual scan, pre-pitch).
- Android vs iOS first — decide by the company's fleet devices.
