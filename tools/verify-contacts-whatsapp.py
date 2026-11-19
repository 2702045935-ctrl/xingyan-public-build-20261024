#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
VIEW = (ROOT / "Sources" / "ContactsView.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("contacts WhatsApp verification failed: " + message)


require("        48\n" in VIEW, "contact avatars must use the compact 48pt row standard")
require(
    "nativeQuickIcon(item, size: 28)" in VIEW
    and ".frame(height: 56)" in VIEW,
    "contact utility rows must use the shared WhatsApp-style icon system",
)
require(
    ".background(contactsSectionFill)" in VIEW,
    "alphabet headers must stay neutral instead of becoming a green block",
)
require(
    "private var funcStrip" in VIEW
    and "RoundedRectangle(cornerRadius: 16, style: .continuous)" not in VIEW,
    "utility contact entries must use dividers without a surrounding selection card",
)
require(
    'Image(systemName: symbol)' in VIEW
    and "RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)" in VIEW,
    "utility contact icons must use compact native SF Symbols with a system tint surface",
)
require(
    ".frame(height: max(72, L.ctRowH))" in VIEW
    and ".padding(.leading, 76)" in VIEW,
    "alphabet contact rows and dividers must share the 48pt avatar geometry",
)

print("contacts-whatsapp: passed")
