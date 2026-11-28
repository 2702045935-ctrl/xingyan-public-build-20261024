#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
API = (ROOT / "Sources" / "API.swift").read_text(encoding="utf-8")
CARD = (ROOT / "Sources" / "NativeMomentRowCell.swift").read_text(encoding="utf-8")
DISCOVER = (ROOT / "Sources" / "DiscoverView.swift").read_text(encoding="utf-8")
FEED = (ROOT / "Sources" / "NativeMomentFeed.swift").read_text(encoding="utf-8")


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
    "card.layer.cornerRadius = 0" in CARD
    and "card.backgroundColor = UIColor(C.pageBg)" in CARD
    and "static let horizontalInset: CGFloat = 22" in CARD
    and "static let trailingInset: CGFloat = 20" in CARD,
    "the native timeline must use the measured open WeChat surface and breathing",
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
    "static let avatar: CGFloat = 43" in CARD
    and "NativeMomentAvatarView(" in CARD
    and "nameLabel.textColor = UIColor(C.link)" in CARD
    and "UIStackView(arrangedSubviews: [avatar, detailStack])" in CARD
    and "detailStack.addArrangedSubview(bodyView)" in CARD
    and "detailStack.addArrangedSubview(mediaCanvas)" in CARD
    and "detailStack.addArrangedSubview(timeLabel)" in CARD,
    "the avatar and all right-column content must share WeChat's measured hierarchy",
)
require(
    "momentProfileFooterHeight" in DISCOVER
    and "headerHeight: L.coverH + momentProfileFooterHeight" in DISCOVER
    and "RemoteImage(path: cover, icon: \"photo\", mode: .fill, maxSide: 2560)"
    in DISCOVER
    and "height: L.coverH + extra" in DISCOVER
    and ".offset(y: 21)" not in DISCOVER
    and "headerContainer.clipsToBounds = false" in FEED,
    "cover must fill edge-to-edge while the signature stays inside the native header",
)

print("moment-editorial: passed")
