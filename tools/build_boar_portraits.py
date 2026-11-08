#!/usr/bin/env python3
"""Build a *reviewable* boar portrait set from Tortoise DB Viewer model thumbnails.
Run: pip install pillow requests
     python tools/build_boar_portraits.py
     python tools/build_boar_portraits.py --source-dir path/to/your/model-thumbs

For an accurate Vanilla unit-frame portrait, use a real in-game screenshot or
render the head with the 1.12 camera. Full-body website thumbs are source
references, NOT equivalent to the in-game portrait camera. This script produces
candidate crops and a contact sheet, but does not activate unreviewed assets.
"""
from __future__ import annotations

import argparse
import io
import json
from pathlib import Path
import requests
from PIL import Image, ImageDraw, ImageChops

ROOT = Path(__file__).resolve().parents[1]
INPUT = ROOT / "tools" / "boar-display-ids.json"
OUT = ROOT / "tools" / "portrait-candidates"
HEADERS = {"User-Agent": "BoarTrackerPortraitBuilder/1.0 (fan reference project)"}


def candidates(display_id: int):
    # Model thumbnails are provided by the same two sources used by the viewer:
    # custom Turtle images (model-thumbs manifest), then Wowhead Classic webthumb.
    # OctoWoW's own database is the final fallback for a rendered full-model view.
    return (
        f"https://xian55.github.io/tortoise-db-viewer/model-thumbs/{display_id}.webp",
        f"https://wow.zamimg.com/modelviewer/classic/webthumbs/npc/{display_id % 256}/{display_id}.webp",
        f"https://octowow.st/db/images/models/{display_id}.png",
    )


def read_source(display_id: int, source_dir: Path | None):
    if source_dir:
        for ext in ("webp", "png", "jpg", "jpeg", "tga"):
            p = source_dir / f"{display_id}.{ext}"
            if p.is_file():
                return Image.open(p).convert("RGBA"), str(p)
        return None, "No local source"
    for url in candidates(display_id):
        try:
            response = requests.get(url, headers=HEADERS, timeout=15)
            response.raise_for_status()
            if not response.headers.get("Content-Type", "").startswith("image/"):
                continue
            im = Image.open(io.BytesIO(response.content)).convert("RGBA")
            if im.width < 32 or im.height < 32:
                continue
            return im, url
        except (requests.RequestException, OSError, ValueError):
            continue
    return None, "No accessible thumbnail"


def crop_candidate(im: Image.Image, display_id: int, size: int = 64):
    """Frame the face, snout and mane instead of only the top of the head.

    This is a crop of a whole-creature model thumbnail, NOT a 1.12 unit-frame
    camera capture. Model 11410 is the sole head-on preview.
    """
    alpha = im.getchannel("A")
    bbox = alpha.point(lambda x: 255 if x > 25 else 0).getbbox()
    if not bbox:
        raise ValueError("empty source")
    left, top, right, bottom = bbox
    w, h = right - left, bottom - top
    if display_id == 11410:
        side = max(16, round(max(w * 0.96, h * 0.74)))
        cx, cy = left + w * 0.52, top + h * 0.36
    else:
        side = max(16, round(max(w, h * 0.88)))
        cx, cy = left + w * 0.47, top + h * 0.44

    box = (
        round(cx - side / 2),
        round(cy - side / 2),
        round(cx + side / 2),
        round(cy + side / 2),
    )
    tile = im.crop(box).resize((size, size), Image.Resampling.LANCZOS)
    # Antialiased circular portrait; transparent corners for map pins.
    mask = Image.new("L", (size * 4, size * 4), 0)
    ImageDraw.Draw(mask).ellipse((2, 2, size * 4 - 3, size * 4 - 3), fill=255)
    mask = mask.resize((size, size), Image.Resampling.LANCZOS)
    tile.putalpha(ImageChops.multiply(tile.getchannel("A"), mask))
    return tile


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-dir", type=Path, help="Use manually downloaded model thumbs offline")
    parser.add_argument("--size", type=int, default=64, choices=[32, 64, 128])
    parser.add_argument("--force", action="store_true", help="Also render already-approved display IDs")
    parser.add_argument("--install", action="store_true", help="Install all 21 candidate TGA portraits after full successful export")
    args = parser.parse_args()
    data = json.loads(INPUT.read_text(encoding="utf-8"))
    ids = sorted({record["displayId"] for record in data["npcs"]})
    approved = set(data["approvedPortraitDisplays"])
    OUT.mkdir(parents=True, exist_ok=True)
    report = []
    thumbs = []
    for did in ids:
        if did in approved and not args.force:
            report.append({"displayId": did, "status": "approved: preserved existing game portrait"})
            continue
        im, url = read_source(did, args.source_dir)
        if im is None:
            report.append({"displayId": did, "status": url})
            continue
        try:
            # Preserve source pixels for independent visual checks and recropping.
            raw_dir = OUT / "sources"
            raw_dir.mkdir(parents=True, exist_ok=True)
            im.save(raw_dir / f"Display_{did}.png", format="PNG")
            tile = crop_candidate(im, did, args.size)
            name = f"Portrait_{did}"
            tile.save(OUT / f"{name}.tga", format="TGA", compression=None)
            tile.resize((96, 96), Image.Resampling.NEAREST).save(OUT / f"{name}.png")
            thumbs.append((did, tile.resize((112, 112), Image.Resampling.NEAREST)))
            report.append({"displayId": did, "status": "candidate requires review", "source": url})
            print(f"{did}: candidate from {url}")
        except (ValueError, OSError) as exc:
            report.append({"displayId": did, "status": str(exc)})
    if thumbs:
        cols = 5
        rows = (len(thumbs) + cols - 1) // cols
        sheet = Image.new("RGB", (cols * 144, rows * 144), "#272727")
        draw = ImageDraw.Draw(sheet)
        for n, (did, tile) in enumerate(thumbs):
            x, y = n % cols * 144, n // cols * 144
            sheet.paste(tile, (x + 16, y + 7), tile)
            draw.text((x + 12, y + 120), f"Display {did}", fill="white")
        sheet.save(OUT / "ContactSheet.png")
    (OUT / "report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"Processed {len(ids)} display IDs; {len(thumbs)} candidates; report at {OUT / 'report.json'}")
    if args.install:
        expected = set(ids) - approved
        found = {did for did, _ in thumbs}
        if found != expected:
            raise SystemExit(f"Refusing partial installation; missing display IDs: {sorted(expected - found)}")
        import shutil
        texture_dir = ROOT / "Textures"
        texture_dir.mkdir(parents=True, exist_ok=True)
        for did in sorted(expected):
            shutil.copyfile(OUT / f"Portrait_{did}.tga", texture_dir / f"Portrait_{did}.tga")
        docs = ROOT / "docs"
        docs.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(OUT / "ContactSheet.png", docs / "BoarPortraits-ContactSheet.png")
        print(f"Installed {len(expected)} model-based portraits to {texture_dir}.")
    print("NOTICE: These are full-body-preview crops, not exact Classic unit-frame camera renders.")


if __name__ == "__main__":
    main()
