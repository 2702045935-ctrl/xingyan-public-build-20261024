#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import shutil
import struct
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def png_has_alpha(path: Path) -> None:
    data = path.read_bytes()
    if not data.startswith(b"\x89PNG\r\n\x1a\n"):
        raise SystemExit(f"not a PNG: {path}")
    width, height = struct.unpack(">II", data[16:24])
    color_type = data[25]
    if (width, height) != (1024, 1024):
        raise SystemExit(f"layer must be 1024x1024: {path}")
    if color_type not in (4, 6):
        raise SystemExit(f"layer must contain alpha: {path}")


def p3(hex_value: str) -> str:
    value = hex_value.lstrip("#")
    if len(value) != 6:
        raise SystemExit(f"expected #RRGGBB: {hex_value}")
    channels = [int(value[index:index + 2], 16) / 255 for index in (0, 2, 4)]
    return "display-p3:" + ",".join(f"{channel:.5f}" for channel in channels) + ",1.00000"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    output = args.output.resolve()
    output = output / "AppIcon.icon" if output.name != "AppIcon.icon" else output
    if output.exists():
        shutil.rmtree(output)
    assets = output / "Assets"
    assets.mkdir(parents=True)

    layers = [
        ("app-icon-liquid-orbit-1024.png", "01-orbit.png", "Orbit", True),
        ("app-icon-liquid-star-1024.png", "02-star-body.png", "Star Body", True),
        ("app-icon-liquid-accents-1024.png", "03-star-detail.png", "Star Detail", False),
    ]
    icon_layers = []
    for source_name, asset_name, layer_name, glass in layers:
        source = ROOT / source_name
        png_has_alpha(source)
        shutil.copy2(source, assets / asset_name)
        icon_layers.append({
            "image-name": asset_name,
            "name": layer_name,
            "glass": glass,
        })

    light_fill = {
        "linear-gradient": [p3("#59DE70"), p3("#1CAD49")],
        "orientation": {
            "start": {"x": 0.18, "y": 0.0},
            "stop": {"x": 0.82, "y": 0.72},
        },
    }
    dark_fill = {
        "linear-gradient": [p3("#145E37"), p3("#073B24")],
        "orientation": {
            "start": {"x": 0.18, "y": 0.0},
            "stop": {"x": 0.82, "y": 0.72},
        },
    }
    manifest = {
        "fill": light_fill,
        "fill-specializations": [
            {"appearance": "dark", "value": dark_fill},
            {"appearance": "tinted", "value": "automatic"},
        ],
        "groups": [
            {
                # Icon Composer stores its layer array front-to-back.
                "name": "Star Orbit",
                "layers": list(reversed(icon_layers)),
                "lighting": "individual",
                "specular": True,
                "shadow": {"kind": "layer-color", "opacity": 0.56},
                "blur-material": 0.18,
                "translucency": {"enabled": True, "value": 0.68},
            }
        ],
        "supported-platforms": {"squares": "shared"},
    }
    (output / "icon.json").write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    print(f"Built layered Liquid Glass icon: {output}")


if __name__ == "__main__":
    main()
