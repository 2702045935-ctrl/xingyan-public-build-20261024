#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PRIVACY = (ROOT / "Sources" / "PrivacyView.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("appearance ambient verification failed: " + message)


require(
    "private struct AppearanceAmbientBackdrop: View" in PRIVACY
    and "AppearanceAmbientBackdrop()" in PRIVACY
    and ".scrollContentBackground(.hidden)" in PRIVACY
    and PRIVACY.count("RadialGradient(") >= 3,
    "appearance settings must render a custom ambient backdrop behind grouped content",
)
require(
    ".repeatForever(autoreverses: true)" in PRIVACY
    and "duration: 14" in PRIVACY
    and "drifting ? proxy.size.width * 0.13" in PRIVACY
    and "Color(hex: 0x7CB9AE)" in PRIVACY
    and "Color(hex: 0x7EA8CE)" in PRIVACY
    and "Color(hex: 0xC9BBA8)" in PRIVACY,
    "ambient light must drift slowly with restrained teal, blue, and warm-gray layers",
)
require(
    "@Environment(\\.accessibilityReduceMotion) private var reduceMotion" in PRIVACY
    and "@Environment(\\.accessibilityReduceTransparency) private var reduceTransparency" in PRIVACY
    and "guard !reduceMotion, !reduceTransparency else { return }" in PRIVACY,
    "ambient animation must respect reduced motion and transparency",
)
require(
    "python3 tools/verify-appearance-ambient.py" in WORKFLOW,
    "appearance ambient verification must run in the iOS gate",
)

print("appearance-ambient: passed")
