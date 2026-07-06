#!/usr/bin/env python3
"""Download and extract the RDD2022 road damage dataset from figshare.

Usage:
    python scripts/download_rdd2022.py [--countries japan india czech norway us china]

RDD2022 (CC BY 4.0): https://doi.org/10.6084/m9.figshare.21431547.v1
Per-country archives are hosted individually on figshare; this script
pulls the ones you ask for (default: all) into data/raw/rdd2022/.
"""
import argparse
import shutil
import sys
import zipfile
from pathlib import Path

import requests
from tqdm import tqdm

# figshare article 21431547 exposes one zip per country as separate files.
# Mapping kept explicit (not queried live) so the script is reproducible;
# verify against https://figshare.com/articles/dataset/21431547 if a link 404s.
FIGSHARE_ARTICLE = "21431547"
COUNTRY_FILES = {
    "japan": "Japan.zip",
    "india": "India.zip",
    "czech": "Czech.zip",
    "norway": "Norway.zip",
    "us": "United_States.zip",
    "china": "China_MotorBike.zip",
}
FIGSHARE_API = f"https://api.figshare.com/v2/articles/{FIGSHARE_ARTICLE}"

DEST_DIR = Path(__file__).resolve().parent.parent / "data" / "raw" / "rdd2022"


def resolve_download_urls() -> dict[str, str]:
    """Query the figshare API for the current per-file download URLs."""
    resp = requests.get(FIGSHARE_API, timeout=30)
    resp.raise_for_status()
    article = resp.json()
    urls = {}
    for f in article.get("files", []):
        name = f["name"]
        for country, fname in COUNTRY_FILES.items():
            if fname.lower() in name.lower():
                urls[country] = f["download_url"]
    return urls


def download_file(url: str, dest: Path) -> None:
    with requests.get(url, stream=True, timeout=60) as r:
        r.raise_for_status()
        total = int(r.headers.get("content-length", 0))
        with open(dest, "wb") as f, tqdm(
            total=total, unit="B", unit_scale=True, desc=dest.name
        ) as bar:
            for chunk in r.iter_content(chunk_size=1 << 20):
                f.write(chunk)
                bar.update(len(chunk))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--countries",
        nargs="+",
        choices=list(COUNTRY_FILES.keys()),
        default=list(COUNTRY_FILES.keys()),
        help="Which country subsets to download (default: all six)",
    )
    parser.add_argument(
        "--skip-extract", action="store_true", help="Download zips only, don't extract"
    )
    args = parser.parse_args()

    DEST_DIR.mkdir(parents=True, exist_ok=True)
    print(f"Resolving current figshare download URLs for article {FIGSHARE_ARTICLE}...")
    urls = resolve_download_urls()

    missing = [c for c in args.countries if c not in urls]
    if missing:
        print(
            f"WARNING: could not resolve URLs for {missing}. "
            "Check https://figshare.com/articles/dataset/21431547 manually.",
            file=sys.stderr,
        )

    for country in args.countries:
        if country not in urls:
            continue
        zip_path = DEST_DIR / COUNTRY_FILES[country]
        if zip_path.exists():
            print(f"[{country}] already downloaded, skipping ({zip_path})")
        else:
            print(f"[{country}] downloading...")
            download_file(urls[country], zip_path)

        if not args.skip_extract:
            extract_dir = DEST_DIR / country
            if extract_dir.exists():
                print(f"[{country}] already extracted, skipping")
                continue
            print(f"[{country}] extracting...")
            with zipfile.ZipFile(zip_path) as zf:
                zf.extractall(extract_dir)

    print(f"\nDone. Data in {DEST_DIR}")
    print("Expected layout per country: <country>/<Country>/{train,test}/{images,annotations/xmls}")


if __name__ == "__main__":
    main()
