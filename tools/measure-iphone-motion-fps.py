#!/usr/bin/env python3
"""Measure FPS only while a USB-driven touch motion is active."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--udid", required=True)
    parser.add_argument("--x", type=float, required=True)
    parser.add_argument("--y", type=float, required=True)
    parser.add_argument("--to-x", type=float, required=True)
    parser.add_argument("--to-y", type=float, required=True)
    parser.add_argument("--repeat", type=int, default=10)
    parser.add_argument("--minimum-fps", type=int, default=50)
    args = parser.parse_args()

    fps = subprocess.Popen(
        [
            sys.executable,
            "-m",
            "pymobiledevice3",
            "developer",
            "dvt",
            "fps",
            "--udid",
            args.udid,
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
        bufsize=1,
    )
    if fps.stdout is None:
        raise RuntimeError("FPS process did not expose stdout")

    try:
        time.sleep(2.0)
        motion = subprocess.run(
            [
                sys.executable,
                str(ROOT / "tools" / "iphone-usb-input.py"),
                "--udid",
                args.udid,
                "--x",
                str(args.x),
                "--y",
                str(args.y),
                "--to-x",
                str(args.to_x),
                "--to-y",
                str(args.to_y),
                "--duration",
                "0.34",
                "--steps",
                "14",
                "--hold",
                "0.01",
                "--repeat",
                str(max(1, args.repeat)),
                "--gap",
                "0.06",
            ],
            check=True,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
        start = None
        end = None
        for line in motion.stdout.splitlines():
            if line.startswith("MOTION_START "):
                start = float(line.split()[1])
            elif line.startswith("MOTION_END "):
                end = float(line.split()[1])
        if start is None or end is None:
            raise RuntimeError("motion process did not report its active interval")

        time.sleep(1.1)
    finally:
        fps.terminate()

    samples: list[int] = []
    assert fps.stdout is not None
    for line in fps.stdout:
        line = line.strip()
        if not line.startswith('{"fps"'):
            continue
        try:
            item = json.loads(line)
            stamp = datetime.fromisoformat(item["timestamp"]).timestamp()
        except (KeyError, ValueError, TypeError):
            continue
        if start + 0.25 <= stamp <= end - 0.05:
            samples.append(int(item["fps"]))

    if not samples:
        raise SystemExit("motion FPS verification failed: no samples during motion")
    minimum = min(samples)
    average = sum(samples) / len(samples)
    print(json.dumps({
        "samples": samples,
        "minimum": minimum,
        "average": round(average, 2),
        "minimum_required": args.minimum_fps,
    }, ensure_ascii=False))
    if minimum < args.minimum_fps:
        raise SystemExit(
            f"motion FPS verification failed: {minimum} < {args.minimum_fps}"
        )
    print("motion-fps: passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
