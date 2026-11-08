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
from PIL import Image, ImageOps, ImageDraw, ImageFont

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


def crop_candidate(im: Image.Image, size: int = 64):
    """Head-biased square crop from the visible rendered creature; review required."""
    alpha = im.getchannel("A")
    bbox = alpha.point(lambda x: 255 if x > 24 else 0).getbbox()
    if not bbox:
        raise ValueError("empty source")
    l, t, r, b = bbox
    w, h = r - l, b - t
    # Most boar source previews face left; start near the upper-left of the
    # bounding box and include the snout and mane. Not a unit-frame camera!
    side = max(16, round(max(w * 0.65, h * 0.43)))
    cx, cy = l + w * 0.35, t + h * 0.31
    left, top = round(cx - side / 2), round(cy - side / 2)
    # Work on a padded canvas so the crop never clips at the picture edge.
    pad = max(im.width, im.height)
    padded = Image.new("RGBA", (im.width + pad * 2, im.height + pad * 2))
    padded.alpha_composite(im, (pad, pad))
    tile = padded.crop((left + pad, top + pad, left + side + pad, top + side + pad))
    tile = tile.resize((size, size), Image.Resampling.LANCZOS)
    # Circular edge is transparent; sprite stays centred inside a square WoW texture.
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, size - 1, size - 1), fill=255)
    tile.putalpha(ImageChops.multiply(tile.getchannel("A"), mask))
    return tile


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-dir", type=Path, help="Use manually downloaded model thumbs offline")
    parser.add_argument("--size", type=int, default=64, choices=[32, 64, 128])
    parser.add_argument("--force", action="store_true", help="Also render already-approved display IDs")
    args = parser.parse_args()
    from PIL import ImageChops
    globals()["ImageChops"] = ImageChops

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
            tile = crop_candidate(im, args.size)
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
    print("IMPORTANT: Inspect ContactSheet.png and compare to real target portraits before activating any candidate.")


if __name__ == "__main__":
    main()
