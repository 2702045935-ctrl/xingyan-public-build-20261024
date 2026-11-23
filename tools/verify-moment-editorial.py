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
    "cornerRadius: AppDesign.Radius.panel" in CARD,
    "the editorial feed must use the refined card surface",
)
require(
    "cornerRadius: AppDesign.Radius.row" in CARD,
    "single photos and video must use the premium media treatment",
)
require(
    "systemTextFont(15.5, .regular, relativeTo: .body)" in CARD
    and "systemTextFont(15.8, .medium, relativeTo: .headline)" in CARD
    and "systemTextFont(11.6, .regular, relativeTo: .caption1)" in CARD,
    "moment copy, author and timestamp must use the compact editorial type scale",
)
require(
    "Text(attribution).foregroundColor(C.link)" in CARD
    and "Text(text).foregroundColor(C.label)" in CARD,
    "comment author attribution must use WeChat link blue while body copy stays primary",
)
require(
    "availableWidth - (cardInset + contentInset) * 2" in CARD,
    "media width must follow the new card insets",
)
require(
    "private var momentTimeline" in DISCOVER
    and "timelineVisibleDay" in DISCOVER
    and "showTimelineDatePicker" in DISCOVER
    and "DatePicker(" in DISCOVER
    and ".datePickerStyle(.graphical)" in DISCOVER
    and "selectedTimelineDate" in DISCOVER,
    "moments must expose an interactive native calendar that selects a specific day",
)
require(
    "private func applyTimelineDate(_ date: Date)" in DISCOVER
    and "private func clearTimelineDateFilter()" in DISCOVER
    and "private func loadMoments(through day: Date) async" in DISCOVER
    and "calendar.isDate(date, inSameDayAs: day)" in DISCOVER,
    "selecting a moment date must filter the feed and fetch older pages when needed",
)
require(
    'formatter.dateFormat = "EEE"' in DISCOVER
    and "if days < 7 { return Self.weekdayFormatter.string(from: d) }" in DISCOVER,
    "moment date sections must cover weekday, month/day and cross-year dates",
)

print("moment-editorial: passed")
