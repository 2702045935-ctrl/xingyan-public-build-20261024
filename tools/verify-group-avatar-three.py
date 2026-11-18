#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
NATIVE = (ROOT / "Sources" / "NativeChatRowCell.swift").read_text(encoding="utf-8")
PROFILE = (ROOT / "Sources" / "Profile.swift").read_text(encoding="utf-8")
MOSAIC = (ROOT / "Sources" / "Core.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("three-member group avatar verification failed: " + message)


require(
    "} else if visibleCount == 3 {" in NATIVE
    and "let largeWidth = (bounds.width - gap) * 0.64" in NATIVE,
    "native group avatars must use the designed three-tile composition",
)
require(
    "} else if users.count == 3 {" in PROFILE
    and "let largeWidth = (geo.size.width - gap) * 0.64" in PROFILE,
    "group creation preview must fill all three slots",
)
require(
    "CGRect(x: 0, y: 0, width: 0.64, height: 1)" in MOSAIC
    and "CGRect(x: 0.64, y: 0, width: 0.36, height: 0.5)" in MOSAIC,
    "shared mosaic must keep the same three-member composition",
)

print("group-avatar-three: passed")
