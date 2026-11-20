#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
API = (ROOT / "Sources" / "API.swift").read_text(encoding="utf-8")
CARD = (ROOT / "Sources" / "MomentFeedCard.swift").read_text(encoding="utf-8")
DISCOVER = (ROOT / "Sources" / "DiscoverView.swift").read_text(encoding="utf-8")


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
    "private func promotionBanner" in CARD,
    "ads must share the regular card skeleton instead of creating a second feed layout",
)
require(
    "RoundedRectangle(cornerRadius: 20, style: .continuous)" in CARD,
    "the editorial feed must use the refined card surface",
)
require(
    "cornerRadius: 16, style: .continuous" in CARD,
    "single photos and video must use the premium media treatment",
)
require(
    "systemTextFont(15.5, .regular, relativeTo: .body)" in CARD
    and "systemTextFont(15.8, .semibold, relativeTo: .headline)" in CARD
    and "systemTextFont(11.6, .regular, relativeTo: .caption1)" in CARD,
    "moment copy, author and timestamp must use the compact editorial type scale",
)
require(
    "availableWidth - (cardInset + contentInset) * 2" in CARD,
    "media width must follow the new card insets",
)
require(
    "private var momentTimeline" in DISCOVER
    and "timelineVisibleDay" in DISCOVER
    and ".opacity(momentsScrollActive && !timelineVisibleDay.isEmpty ? 1 : 0)" in DISCOVER
    and ".allowsHitTesting(false)" in DISCOVER,
    "moments must show a non-interactive native date timeline only while scrolling",
)
require(
    'formatter.dateFormat = "EEE"' in DISCOVER
    and "if days < 7 { return Self.weekdayFormatter.string(from: d) }" in DISCOVER,
    "moment date sections must cover weekday, month/day and cross-year dates",
)

print("moment-editorial: passed")
