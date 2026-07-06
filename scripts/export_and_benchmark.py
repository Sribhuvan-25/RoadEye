#!/usr/bin/env python3
"""Phase 0, gate 1: export a YOLO model to edge formats and benchmark inference speed.

This does NOT tell you the real on-phone FPS — no desktop can simulate a
phone's NPU/GPU delegate. What it gives you:
  1. Working exported artifacts (TFLite INT8/FP16, CoreML) to drop into the
     phone app for the real test.
  2. A same-machine speed comparison across model sizes/formats, useful for
     picking which variant to carry forward.

Usage:
    python scripts/export_and_benchmark.py --model yolo26n.pt --imgsz 640
    python scripts/export_and_benchmark.py --model yolov8n-seg.pt --formats tflite coreml

Next step after this script: sideload the .tflite (Android) or .mlpackage
(iOS) into a minimal camera test harness on the actual target phone and
measure wall-clock FPS there. That number is the real Phase 0 gate.
"""
import argparse
import platform
import time
from pathlib import Path

from ultralytics import YOLO

MODELS_DIR = Path(__file__).resolve().parent.parent / "models"
BENCH_DIR = Path(__file__).resolve().parent.parent / "benchmarks"

SUPPORTED_FORMATS = {
    "tflite": {"format": "tflite", "int8": True},
    "coreml": {"format": "coreml", "int8": False},  # coremltools handles its own quantization
    "onnx": {"format": "onnx", "int8": False},
}


def export_model(model_path: str, formats: list[str], imgsz: int) -> dict[str, Path]:
    model = YOLO(model_path)
    exported = {}
    for fmt in formats:
        opts = SUPPORTED_FORMATS[fmt]
        print(f"\n=== Exporting {model_path} -> {fmt} (imgsz={imgsz}) ===")
        out_path = Path(model.export(imgsz=imgsz, **opts))
        dest = MODELS_DIR / out_path.name
        out_path.replace(dest)
        exported[fmt] = dest
    return exported


def benchmark_pytorch(model_path: str, imgsz: int, iters: int) -> float:
    """Baseline: original .pt on whatever device is available locally (CPU/MPS/CUDA)."""
    model = YOLO(model_path)
    dummy = _dummy_image_path(imgsz)

    # warmup
    for _ in range(5):
        model.predict(dummy, imgsz=imgsz, verbose=False)

    start = time.perf_counter()
    for _ in range(iters):
        model.predict(dummy, imgsz=imgsz, verbose=False)
    elapsed = time.perf_counter() - start
    return iters / elapsed


def _dummy_image_path(imgsz: int) -> str:
    import numpy as np
    from PIL import Image

    path = BENCH_DIR / f"_dummy_{imgsz}.jpg"
    if not path.exists():
        arr = (np.random.rand(imgsz, imgsz, 3) * 255).astype("uint8")
        Image.fromarray(arr).save(path)
    return str(path)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", default="yolo26n.pt", help="Ultralytics model name or .pt path")
    parser.add_argument("--imgsz", type=int, default=640)
    parser.add_argument(
        "--formats", nargs="+", default=["tflite", "coreml", "onnx"], choices=list(SUPPORTED_FORMATS)
    )
    parser.add_argument("--iters", type=int, default=50, help="Iterations for the local PyTorch baseline timing")
    parser.add_argument("--skip-export", action="store_true", help="Only run the local PyTorch baseline")
    args = parser.parse_args()

    MODELS_DIR.mkdir(parents=True, exist_ok=True)
    BENCH_DIR.mkdir(parents=True, exist_ok=True)

    print(f"Host: {platform.platform()} / {platform.processor()}")
    print(f"Model: {args.model}")

    fps = benchmark_pytorch(args.model, args.imgsz, args.iters)
    print(f"\nLocal PyTorch baseline: {fps:.1f} FPS @ {args.imgsz}px "
          f"(NOT representative of phone/Jetson performance)")

    if args.skip_export:
        return

    exported = export_model(args.model, args.formats, args.imgsz)

    report_path = BENCH_DIR / f"export_report_{Path(args.model).stem}.md"
    with open(report_path, "w") as f:
        f.write(f"# Export report — {args.model}\n\n")
        f.write(f"Host: {platform.platform()}\n\n")
        f.write(f"Local PyTorch baseline: {fps:.1f} FPS @ {args.imgsz}px "
                "(desktop CPU/GPU — not the real gate)\n\n")
        f.write("## Exported artifacts\n\n")
        for fmt, path in exported.items():
            f.write(f"- **{fmt}**: `{path}`\n")
        f.write("\n## Next step (the real Phase 0 gate)\n\n")
        f.write(
            "Copy the .tflite into an Android test harness (or .mlpackage into an "
            "iOS one) on the actual target phone and measure sustained FPS on live "
            "camera frames at this imgsz. Record results here manually:\n\n"
            "| Device | Format | FPS | Notes |\n|---|---|---|---|\n"
            "| | | | |\n"
        )
    print(f"\nReport written to {report_path}")


if __name__ == "__main__":
    main()
