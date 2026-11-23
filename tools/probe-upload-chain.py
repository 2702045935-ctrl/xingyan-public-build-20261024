from __future__ import annotations

import argparse
import io
import os
import plistlib
import secrets
import subprocess
import tempfile
import time
from pathlib import Path

import requests
from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_PREFS = ROOT / "diagnostics" / "chris-prefs.plist"
FFMPEG = Path(r"C:\Users\Administrator\ffmpeg\bin\ffmpeg.exe")


def elapsed_ms(start: float) -> int:
    return round((time.monotonic() - start) * 1000)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--prefs", default=str(DEFAULT_PREFS))
    parser.add_argument("--base", default="")
    parser.add_argument("--sizes", default="")
    args = parser.parse_args()

    with Path(args.prefs).open("rb") as file:
        prefs = plistlib.load(file)
    token = str(prefs.get("chris.token") or "")
    host = str(prefs.get("chris.server") or "").strip()
    if not token or not host:
        raise SystemExit("test token or server missing")

    session = requests.Session()
    session.verify = False
    headers = {"Authorization": "Bearer " + token}

    image = Image.new("RGB", (2048, 1536), (6, 8, 12))
    draw = ImageDraw.Draw(image)
    draw.rectangle((128, 192, 1920, 1344), fill=(30, 92, 170))
    draw.ellipse((680, 500, 1368, 1188), fill=(235, 240, 248))
    image_bytes = io.BytesIO()
    image.save(image_bytes, format="JPEG", quality=88, optimize=True)

    requested_sizes = {
        int(value)
        for value in str(args.sizes).split(",")
        if value.strip().isdigit()
    }
    file_size_mb = next(iter(sorted(requested_sizes)), 5)
    file_bytes = (
        b"xingyan-upload-probe\n"
        + secrets.token_bytes(file_size_mb * 1024 * 1024)
    )
    with tempfile.TemporaryDirectory(prefix="xingyan-upload-") as td:
        video_path = Path(td) / "probe.mp4"
        subprocess.run(
            [
                str(FFMPEG),
                "-y",
                "-loglevel",
                "error",
                "-f",
                "lavfi",
                "-i",
                "testsrc2=s=640x360:d=3:r=30",
                "-c:v",
                "libx264",
                "-pix_fmt",
                "yuv420p",
                "-movflags",
                "+faststart",
                str(video_path),
            ],
            check=True,
        )
        video_bytes = video_path.read_bytes()

    cases = [
        ("image_3mp", image_bytes.getvalue(), "image/jpeg"),
        (f"file_{file_size_mb}mb", file_bytes, "application/octet-stream"),
        ("video_3s", video_bytes, "video/mp4"),
    ]

    base = str(args.base or "").rstrip("/")
    if not base:
        base = host if host.startswith(("http://", "https://")) else "https://" + host
        if host == "mail.xingyanmail.site:443":
            base += "/xy"
    for name, payload, mime in cases:
        upload_headers = dict(headers)
        upload_headers["Content-Type"] = mime
        upload_headers["x-chris-compressed"] = "1"
        started = time.monotonic()
        response = session.post(
            base + "/api/upload/raw",
            data=payload,
            headers=upload_headers,
            timeout=180,
        )
        upload_ms = elapsed_ms(started)
        response.raise_for_status()
        body = response.json()
        url = ((body.get("data") or {}).get("url") or body.get("url") or "")
        if not url.startswith("/uploads/"):
            raise AssertionError(f"{name}: invalid upload response")

        started = time.monotonic()
        download = session.get(base + url, headers=headers, timeout=180)
        download_ms = elapsed_ms(started)
        download.raise_for_status()
        if not download.content:
            raise AssertionError(f"{name}: empty download")
        print(
            name,
            "upload_ms", upload_ms,
            "upload_bytes", len(payload),
            "download_ms", download_ms,
            "download_bytes", len(download.content),
            "status", download.status_code,
        )


if __name__ == "__main__":
    main()
