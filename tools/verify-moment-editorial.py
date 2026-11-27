#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
API = (ROOT / "Sources" / "API.swift").read_text(encoding="utf-8")
CARD = (ROOT / "Sources" / "NativeMomentRowCell.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("moment editorial verification failed: " + message)


require(
    "struct MomentPromotion: Codable, Hashable" in API,
    "moments must expose optional sponsored-content metadata",
)
require(
    "var promotion: MomentPromotion? = nil" in API,
    "existing moments must keep decoding without ad metadata",
)
require(
    "configurePromotion" in CARD
    and "NativeMomentRowCell: UITableViewCell" in CARD,
    "ads must share the native card skeleton instead of creating a second feed layout",
)
require(
    "card.layer.cornerRadius = 22" in CARD
    and "card.layer.cornerCurve = .continuous" in CARD,
    "the native editorial feed must use the refined card surface",
)
require(
    "radius: MomentMediaLayout.singleRadius" in CARD
    and "radius: 18" in CARD,
    "single photos and video must use the premium native media treatment",
)
require(
    "momentUIFont(16.5, .regular, relativeTo: .body)" in CARD,
    "moment copy must use the refined editorial type scale",
)
require(
    "(window?.bounds.width ?? L.width) - 52" in CARD,
    "native media width must preserve the existing card insets",
)

print("moment-editorial: passed")
