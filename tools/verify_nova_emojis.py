from __future__ import annotations

import json
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
PACK_DIR = ROOT / "server" / "public" / "emoji" / "nova-courier"
PACK_ID = "nova-courier-premium"
CATEGORY_ID = "xingyan-original"
EXPECTED_SIZE = (320, 320)
EXPECTED_FRAMES = 20


def main() -> None:
    catalog = json.loads((PACK_DIR / "pack.json").read_text(encoding="utf-8"))
    manifest = json.loads((PACK_DIR / "manifest.json").read_text(encoding="utf-8"))
    categories = {item["id"] for item in catalog.get("categories", [])}
    if CATEGORY_ID not in categories:
        raise SystemExit("missing Xingyan original sticker category")

    packs = [item for item in catalog.get("packs", []) if item.get("id") == PACK_ID]
    if len(packs) != 1:
        raise SystemExit("Nova Courier pack must appear exactly once")
    pack = packs[0]
    if pack.get("category") != CATEGORY_ID:
        raise SystemExit("Nova Courier is not in the Xingyan original category")

    files = pack.get("files") or []
    manifest_files = [item["file"] for item in manifest.get("items", [])]
    if files != manifest_files:
        raise SystemExit("pack.json and manifest.json disagree on file order")
    if len(files) != 16:
        raise SystemExit(f"expected 16 stickers, got {len(files)}")

    for name in files:
        path = PACK_DIR / name
        if not path.is_file():
            raise SystemExit(f"missing sticker: {name}")
        if path.stat().st_size > 450_000:
            raise SystemExit(f"sticker exceeds mobile size budget: {name}")

        image = Image.open(path)
        if image.size != EXPECTED_SIZE:
            raise SystemExit(f"{name}: unexpected canvas {image.size}")
        if getattr(image, "n_frames", 1) != EXPECTED_FRAMES:
            raise SystemExit(f"{name}: unexpected frame count {getattr(image, 'n_frames', 1)}")

        image.seek(0)
        box = image.convert("RGBA").getchannel("A").getbbox()
        if box is None:
            raise SystemExit(f"{name}: fully transparent thumbnail frame")
        left, top, right, bottom = box
        if left < 16 or top < 16 or right > 304 or bottom > 304:
            raise SystemExit(f"{name}: artwork is clipped at the canvas edge")

    icon = Image.open(PACK_DIR / "icon.gif")
    if icon.size != EXPECTED_SIZE or getattr(icon, "n_frames", 1) != EXPECTED_FRAMES:
        raise SystemExit("pack icon has the wrong format")

    preview = Image.open(PACK_DIR / "preview.png")
    if preview.width < 1100 or preview.height < 1200:
        raise SystemExit("preview sheet is missing or too small")

    print(f"Nova Courier OK: {len(files)} stickers, {EXPECTED_FRAMES} frames each")


if __name__ == "__main__":
    main()
