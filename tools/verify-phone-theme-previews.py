#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PRIVACY = (ROOT / "Sources" / "PrivacyView.swift").read_text(encoding="utf-8")
THEMES = (ROOT / "Sources" / "ChatThemes.swift").read_text(encoding="utf-8")
WALLPAPER = (ROOT / "Sources" / "ChatBackgroundSheet.swift").read_text(encoding="utf-8")
WEATHER = (ROOT / "Sources" / "PlatformAcademy.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("phone preview verification failed: " + message)


require(
    ".frame(width: 128, height: 238)" in PRIVACY,
    "appearance choices must use a refined portrait phone preview",
)
require(
    "RoundedRectangle(cornerRadius: 25, style: .continuous)" in PRIVACY
    and "Capsule()\n                .fill(Color.black)\n                .frame(width: 31, height: 8)"
    in PRIVACY
    and "private var appGrid: some View" in PRIVACY,
    "the appearance phone previews must include a device frame, Dynamic Island, and home screen",
)
require(
    ".frame(maxWidth: .infinity)\n        .frame(height: 214)" in THEMES,
    "chat theme detail preview must use a responsive full-width canvas",
)
require(
    ".frame(width: 50, height: 68)" in THEMES,
    "each theme row must include a compact miniature phone preview",
)
require(
    ".frame(width: 214, height: 408)" in WALLPAPER,
    "the chat wallpaper picker must preview the full phone screen",
)
require(
    'Text("9:41")' in WALLPAPER and "battery.75" in WALLPAPER,
    "the wallpaper phone preview must include a native status bar",
)
require(
    "hourlyForecast" in WEATHER and "dailyForecast" in WEATHER,
    "the bundled weather system must include hourly and daily forecasts",
)

print("phone-theme-previews: passed")
