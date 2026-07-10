#!/usr/bin/env python3
"""Create a train/val split + data.yaml for a YOLO-format dataset.

Works on the Kaggle "Road Damage Dataset: Potholes, Cracks and Manholes"
(data/raw/road-damage-dataset/data/{images,labels-YOLO}) by default, but any
flat images/ + labels/ pair with matching filenames works via --images-dir
and --labels-dir.

Symlinks images/labels into data/processed/<name>/{train,val}/{images,labels}
rather than copying, to save disk space.

Usage:
    python scripts/prepare_yolo_split.py --name potholes-cracks-manholes \
        --images-dir data/raw/road-damage-dataset/data/images \
        --labels-dir data/raw/road-damage-dataset/data/labels-YOLO \
        --classes Pothole Crack Manhole \
        --val-frac 0.15
"""
import argparse
import os
import random
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--name", required=True, help="Dataset name, used as output dir under data/processed/")
    parser.add_argument("--images-dir", required=True, type=Path)
    parser.add_argument("--labels-dir", required=True, type=Path)
    parser.add_argument("--classes", required=True, nargs="+", help="Class names in class-id order")
    parser.add_argument("--val-frac", type=float, default=0.15)
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args()

    images_dir = args.images_dir.resolve()
    labels_dir = args.labels_dir.resolve()
    out_dir = ROOT / "data" / "processed" / args.name

    image_files = sorted(
        f for f in images_dir.iterdir() if f.suffix.lower() in (".jpg", ".jpeg", ".png")
    )
    pairs = []
    skipped = 0
    for img in image_files:
        lbl = labels_dir / f"{img.stem}.txt"
        if lbl.exists():
            pairs.append((img, lbl))
        else:
            skipped += 1
    if skipped:
        print(f"WARNING: {skipped} images had no matching label file, skipped")

    random.Random(args.seed).shuffle(pairs)
    n_val = int(len(pairs) * args.val_frac)
    val_pairs, train_pairs = pairs[:n_val], pairs[n_val:]

    for split, split_pairs in (("train", train_pairs), ("val", val_pairs)):
        img_out = out_dir / split / "images"
        lbl_out = out_dir / split / "labels"
        img_out.mkdir(parents=True, exist_ok=True)
        lbl_out.mkdir(parents=True, exist_ok=True)
        for img, lbl in split_pairs:
            _symlink(img, img_out / img.name)
            _symlink(lbl, lbl_out / lbl.name)
        print(f"{split}: {len(split_pairs)} images -> {img_out}")

    yaml_path = out_dir / "data.yaml"
    with open(yaml_path, "w") as f:
        f.write(f"path: {out_dir}\n")
        f.write("train: train/images\n")
        f.write("val: val/images\n")
        f.write(f"nc: {len(args.classes)}\n")
        f.write(f"names: {args.classes}\n")

    print(f"\nWrote {yaml_path}")
    print(f"Total: {len(pairs)} pairs ({len(train_pairs)} train / {len(val_pairs)} val)")


def _symlink(src: Path, dest: Path) -> None:
    if dest.exists() or dest.is_symlink():
        dest.unlink()
    os.symlink(src, dest)


if __name__ == "__main__":
    main()
