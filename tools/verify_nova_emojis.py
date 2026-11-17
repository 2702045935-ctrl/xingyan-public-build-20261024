from __future__ import annotations

import json
import struct
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PACK_DIR = ROOT / "server" / "public" / "emoji" / "nova-courier"
PACK_ID = "nova-courier-premium"
CATEGORY_ID = "xingyan-original"
EXPECTED_SIZE = (320, 320)
EXPECTED_FRAMES = 20


def _skip_gif_subblocks(data: bytes, offset: int) -> int:
    while True:
        if offset >= len(data):
            raise ValueError("truncated GIF sub-block")
        size = data[offset]
        offset += 1
        if size == 0:
            return offset
        offset += size


def _gif_info(path: Path) -> tuple[tuple[int, int], int, bool]:
    data = path.read_bytes()
    if data[:6] not in (b"GIF87a", b"GIF89a") or len(data) < 13:
        raise ValueError("invalid GIF header")
    width, height = struct.unpack_from("<HH", data, 6)
    packed = data[10]
    offset = 13
    if packed & 0x80:
        offset += 3 * (1 << ((packed & 0x07) + 1))

    frames = 0
    transparent = False
    while offset < len(data):
        marker = data[offset]
        offset += 1
        if marker == 0x3B:
            break
        if marker == 0x21:
            if offset >= len(data):
                raise ValueError("truncated GIF extension")
            label = data[offset]
            offset += 1
            if label == 0xF9:
                if offset >= len(data) or data[offset] != 4:
                    raise ValueError("invalid GIF control extension")
                offset += 1
                if offset + 4 > len(data):
                    raise ValueError("truncated GIF control extension")
                transparent = transparent or bool(data[offset] & 0x01)
                offset += 4
                if offset >= len(data) or data[offset] != 0:
                    raise ValueError("invalid GIF control terminator")
                offset += 1
            else:
                offset = _skip_gif_subblocks(data, offset)
        elif marker == 0x2C:
            frames += 1
            if offset + 9 > len(data):
                raise ValueError("truncated GIF image descriptor")
            packed_image = data[offset + 8]
            offset += 9
            if packed_image & 0x80:
                offset += 3 * (1 << ((packed_image & 0x07) + 1))
            if offset >= len(data):
                raise ValueError("missing GIF LZW code size")
            offset += 1
            offset = _skip_gif_subblocks(data, offset)
        else:
            raise ValueError(f"unexpected GIF block 0x{marker:02X}")
    return (width, height), frames, transparent


def _png_size(path: Path) -> tuple[int, int]:
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n" or len(data) < 24 or data[12:16] != b"IHDR":
        raise ValueError("invalid PNG header")
    return struct.unpack_from(">II", data, 16)


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

        try:
            size, frames, transparent = _gif_info(path)
        except ValueError as error:
            raise SystemExit(f"{name}: {error}") from error
        if size != EXPECTED_SIZE:
            raise SystemExit(f"{name}: unexpected canvas {size}")
        if frames != EXPECTED_FRAMES:
            raise SystemExit(f"{name}: unexpected frame count {frames}")
        if not transparent:
            raise SystemExit(f"{name}: GIF has no transparent frame marker")

    icon_size, icon_frames, icon_transparent = _gif_info(PACK_DIR / "icon.gif")
    if (icon_size != EXPECTED_SIZE or icon_frames != EXPECTED_FRAMES
            or not icon_transparent):
        raise SystemExit("pack icon has the wrong format")

    preview_width, preview_height = _png_size(PACK_DIR / "preview.png")
    if preview_width < 1100 or preview_height < 1200:
        raise SystemExit("preview sheet is missing or too small")

    print(f"Nova Courier OK: {len(files)} stickers, {EXPECTED_FRAMES} frames each")


if __name__ == "__main__":
    main()
