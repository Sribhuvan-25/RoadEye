"""Kaggle GPU training script — YOLO11n on Potholes/Cracks/Manholes + RDD2022.

Runs as a Kaggle script kernel with the dataset
`lorenzoarcioni/road-damage-dataset-potholes-cracks-and-manholes` attached
(read-only at /kaggle/input/). Additionally downloads the RDD2022 Czech
subset directly (internet must be enabled on the kernel) and converts its
Pascal VOC XML annotations to our 3-class YOLO scheme:
  D00 (longitudinal crack), D10 (transverse), D20 (alligator) -> Crack
  D40 (pothole) -> Pothole
  (RDD2022 has no manhole class; those images simply contribute no
  Manhole labels, which is fine for training.)
Other D-codes (D43/D44/D50 crosswalk/paint/manhole-cover variants some
country subsets carry) are dropped -- not part of our taxonomy.

Validation uses a FROZEN holdout: the original 15% val split of the base
dataset (seed 42), identical across all runs so metrics stay comparable.
All extra data sources go to train only. Trains 100 epochs, leaving
weights + results in /kaggle/working/.
"""
import random
import shutil
import subprocess
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

subprocess.run(["pip", "install", "-q", "ultralytics"], check=True)

import requests  # noqa: E402
import torch  # noqa: E402
from ultralytics import YOLO  # noqa: E402

# Kaggle's free GPU pool includes both T4 (sm_75, supported by current
# PyTorch wheels) and older P100 (sm_60, dropped from recent wheels) --
# which one you get is not selectable via the API. Detect incompatibility
# and fall back to CPU rather than crash mid-training.
DEVICE = 0
if torch.cuda.is_available():
    try:
        cap = torch.cuda.get_device_capability(0)
        supported = torch.cuda.get_arch_list()
        sm = f"sm_{cap[0]}{cap[1]}"
        if not any(sm in arch for arch in supported):
            print(
                f"GPU {torch.cuda.get_device_name(0)} ({sm}) not supported by "
                f"this PyTorch build ({supported}) -- falling back to CPU."
            )
            DEVICE = "cpu"
    except Exception as e:  # pragma: no cover - defensive
        print(f"GPU capability check failed ({e}); falling back to CPU.")
        DEVICE = "cpu"
else:
    DEVICE = "cpu"
print(f"Training device: {DEVICE}")

WORK = Path("/kaggle/working")
SPLIT_DIR = WORK / "dataset"
RDD_DIR = WORK / "rdd2022_czech"
CLASSES = ["Pothole", "Crack", "Manhole"]
VAL_FRAC = 0.15
SEED = 42          # same seed as scripts/prepare_yolo_split.py -> same split
MODEL = "yolo11n.pt"
EPOCHS = 100
IMGSZ = 640

RDD_CZECH_URL = (
    "https://bigdatacup.s3.ap-northeast-1.amazonaws.com/2022/CRDDC2022/RDD2022/"
    "Country_Specific_Data_CRDDC2022/RDD2022_Czech.zip"
)
# RDD taxonomy -> our 3-class scheme. Codes not listed here (D43/D44/D50 etc,
# present in some country subsets) are dropped -- not part of our taxonomy.
RDD_CLASS_MAP = {"D00": "Crack", "D10": "Crack", "D20": "Crack", "D40": "Pothole"}

# ---- locate the attached Kaggle dataset (mount dir name can vary) ----
input_root = Path("/kaggle/input")
print("Contents of /kaggle/input:", list(input_root.iterdir()))

images_dir = labels_dir = None
for candidate in input_root.rglob("images"):
    sibling_labels = candidate.parent / "labels-YOLO"
    if sibling_labels.is_dir():
        images_dir, labels_dir = candidate, sibling_labels
        break

if images_dir is None:
    raise FileNotFoundError(
        f"Could not find an images/ + labels-YOLO/ pair under {input_root}. "
        f"Found: {list(input_root.rglob('*'))[:50]}"
    )
print(f"Using images_dir={images_dir}, labels_dir={labels_dir}")

pairs = []


def add_yolo_pairs(images_dir, labels_dir):
    image_files = sorted(
        f for f in images_dir.iterdir() if f.suffix.lower() in (".jpg", ".jpeg", ".png")
    )
    found = [(img, labels_dir / f"{img.stem}.txt") for img in image_files]
    found = [(i, l) for i, l in found if l.exists()]
    pairs.extend(found)
    return len(found)


n_kaggle = add_yolo_pairs(images_dir, labels_dir)
print(f"Potholes/Cracks/Manholes dataset: {n_kaggle} labeled images")

# ---- FROZEN HOLDOUT: reproduce the ORIGINAL 15% val split of the base
# dataset (seed 42 over the base dataset alone, matching
# scripts/prepare_yolo_split.py) and pin it as the validation set for THIS
# and every future run. Extra data sources (RDD2022 etc.) go to train only.
# This keeps every run's metrics comparable and prevents the train/val
# leakage that a re-shuffle over the combined pool caused previously.
base_pairs = list(pairs)
random.Random(SEED).shuffle(base_pairs)
n_holdout = int(len(base_pairs) * VAL_FRAC)
holdout_pairs = base_pairs[:n_holdout]
holdout_names = {img.name for img, _ in holdout_pairs}
print(f"Frozen holdout: {len(holdout_pairs)} images (original base-dataset val split)")

# ---- download + convert RDD2022 Czech (Pascal VOC XML -> our YOLO classes) ----
print(f"Downloading RDD2022 Czech from {RDD_CZECH_URL} ...")
zip_path = WORK / "RDD2022_Czech.zip"
with requests.get(RDD_CZECH_URL, stream=True, timeout=120) as r:
    r.raise_for_status()
    with open(zip_path, "wb") as f:
        for chunk in r.iter_content(chunk_size=1 << 20):
            f.write(chunk)
print(f"Downloaded {zip_path.stat().st_size / 1e6:.1f} MB, extracting...")
with zipfile.ZipFile(zip_path) as zf:
    zf.extractall(RDD_DIR)
zip_path.unlink()

rdd_images_dir = next(RDD_DIR.rglob("train/images"))
rdd_ann_dir = next(RDD_DIR.rglob("train/annotations/xmls"))
print(f"RDD2022 Czech: images={rdd_images_dir}, annotations={rdd_ann_dir}")

rdd_yolo_labels_dir = WORK / "rdd2022_czech_yolo_labels"
rdd_yolo_labels_dir.mkdir(parents=True, exist_ok=True)

n_rdd_converted = n_rdd_skipped_empty = 0
for xml_path in rdd_ann_dir.glob("*.xml"):
    tree = ET.parse(xml_path)
    root = tree.getroot()
    size = root.find("size")
    img_w, img_h = int(size.find("width").text), int(size.find("height").text)

    yolo_lines = []
    for obj in root.findall("object"):
        rdd_class = obj.find("name").text
        our_class = RDD_CLASS_MAP.get(rdd_class)
        if our_class is None:
            continue  # not in our taxonomy (e.g. D43/D44/D50)
        cls_id = CLASSES.index(our_class)
        box = obj.find("bndbox")
        xmin, ymin = float(box.find("xmin").text), float(box.find("ymin").text)
        xmax, ymax = float(box.find("xmax").text), float(box.find("ymax").text)
        xc = ((xmin + xmax) / 2) / img_w
        yc = ((ymin + ymax) / 2) / img_h
        w = (xmax - xmin) / img_w
        h = (ymax - ymin) / img_h
        yolo_lines.append(f"{cls_id} {xc:.6f} {yc:.6f} {w:.6f} {h:.6f}")

    if not yolo_lines:
        n_rdd_skipped_empty += 1
        continue  # image has no boxes in our taxonomy -- skip, not a useful negative here
    (rdd_yolo_labels_dir / f"{xml_path.stem}.txt").write_text("\n".join(yolo_lines))
    n_rdd_converted += 1

print(
    f"RDD2022 Czech: converted {n_rdd_converted} images with in-taxonomy boxes "
    f"({n_rdd_skipped_empty} skipped, no D00/D10/D20/D40 boxes)"
)
n_rdd = add_yolo_pairs(rdd_images_dir, rdd_yolo_labels_dir)
print(f"RDD2022 Czech: {n_rdd} labeled images added to training pool")

print(f"Combined dataset: {len(pairs)} labeled images total")

# ---- build split: frozen holdout = val; everything else = train ----
train_pairs = [(i, l) for i, l in pairs if i.name not in holdout_names]
splits = {"val": holdout_pairs, "train": train_pairs}

for split, split_pairs in splits.items():
    img_out = SPLIT_DIR / split / "images"
    lbl_out = SPLIT_DIR / split / "labels"
    img_out.mkdir(parents=True, exist_ok=True)
    lbl_out.mkdir(parents=True, exist_ok=True)
    seen_names = set()
    for img, lbl in split_pairs:
        # two source datasets could in principle share a filename -- disambiguate
        name = img.name
        if name in seen_names:
            name = f"{img.stem}__{img.parent.parent.parent.name}{img.suffix}"
        seen_names.add(name)
        shutil.copy(img, img_out / name)
        shutil.copy(lbl, lbl_out / f"{Path(name).stem}.txt")
    print(f"{split}: {len(split_pairs)} images")

yaml_path = SPLIT_DIR / "data.yaml"
yaml_path.write_text(
    f"path: {SPLIT_DIR}\n"
    "train: train/images\n"
    "val: val/images\n"
    f"nc: {len(CLASSES)}\n"
    f"names: {CLASSES}\n"
)

# ---- train ----
model = YOLO(MODEL)
model.train(
    data=str(yaml_path),
    epochs=EPOCHS,
    imgsz=IMGSZ,
    project=str(WORK / "runs"),
    name="yolo11n_100ep",
    device=DEVICE,
)

# ---- surface artifacts for download ----
run_dir = WORK / "runs" / "yolo11n_100ep"
shutil.copy(run_dir / "weights" / "best.pt", WORK / "best.pt")
shutil.copy(run_dir / "results.csv", WORK / "results.csv")

# validation summary for the log
metrics = YOLO(str(WORK / "best.pt")).val(data=str(yaml_path))
print("Final mAP50:", metrics.box.map50)
print("Final mAP50-95:", metrics.box.map)

# keep output size sane: drop the split copy (it's reproducible)
shutil.rmtree(SPLIT_DIR, ignore_errors=True)
