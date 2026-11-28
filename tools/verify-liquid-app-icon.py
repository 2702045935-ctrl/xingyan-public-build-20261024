#!/usr/bin/env python3
from pathlib import Path
import json
import struct
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)
PREPARER = (ROOT / "tools" / "prepare-liquid-icon.sh").read_text(encoding="utf-8")
INFO = (ROOT / "Info.plist").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("liquid app icon verification failed: " + message)


require(
    "<key>CFBundleIconName</key>" in INFO
    and "<string>AppIcon</string>" in INFO,
    "the bundle must select the AppIcon asset catalog instead of only loose PNGs",
)
require(
    "bash tools/prepare-liquid-icon.sh ." in WORKFLOW
    and "xcrun actool AppIcon.icon Assets.xcassets" in WORKFLOW
    and "--app-icon AppIcon" in WORKFLOW
    and "--include-all-app-icons" in WORKFLOW,
    "Xcode 26 must compile the layered iOS icon catalog and all generated sizes",
)
require(
    "tools/build-liquid-icon-package.py" in PREPARER
    and "AppIcon.icon" in PREPARER,
    "the build must produce a layered Icon Composer package",
)
for name in (
    "app-icon-liquid-orbit-1024.png",
    "app-icon-liquid-star-1024.png",
    "app-icon-liquid-accents-1024.png",
):
    data = (ROOT / name).read_bytes()
    require(data.startswith(b"\x89PNG\r\n\x1a\n"), f"{name} must be PNG")
    width, height = struct.unpack(">II", data[16:24])
    require((width, height) == (1024, 1024), f"{name} must be 1024x1024")
    require(data[25] in (4, 6), f"{name} must contain alpha")

with tempfile.TemporaryDirectory() as temp:
    subprocess.run(
        [
            sys.executable,
            str(ROOT / "tools" / "build-liquid-icon-package.py"),
            "--output",
            temp,
        ],
        check=True,
        stdout=subprocess.DEVNULL,
    )
    package = Path(temp) / "AppIcon.icon"
    manifest = json.loads((package / "icon.json").read_text(encoding="utf-8"))
    require(len(manifest.get("groups", [])) == 1, "one composed icon group is required")
    group = manifest["groups"][0]
    require(
        group.get("lighting") == "individual"
        and group.get("specular") is True
        and group.get("shadow", {}).get("kind") == "layer-color",
        "system specular lighting and depth shadow must stay enabled",
    )
    require(
        len(group.get("layers", [])) == 3
        and manifest.get("fill-specializations", [])[0].get("appearance") == "dark"
        and manifest.get("fill-specializations", [])[1].get("appearance") == "tinted",
        "orbit, star body, detail, dark and tinted variants must be packaged",
    )
    for layer in group["layers"]:
        require(
            (package / "Assets" / layer["image-name"]).is_file(),
            f"missing icon layer {layer['image-name']}",
        )

print("liquid-app-icon: passed")
