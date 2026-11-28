#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DISCOVER = (ROOT / "Sources" / "DiscoverView.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("moment cover design verification failed: " + message)


start = DISCOVER.index("private func coverView(_ extra: CGFloat)")
end = DISCOVER.index("private func dayLabel", start)
cover = DISCOVER[start:end]

require(
    "size: max(58, L.coverAvatar)" in cover
    and "radius: 16" in cover
    and ".padding(.leading, 22)" in cover
    and ".padding(.trailing, 92)" in cover
    and ".padding(.bottom, 12)" in cover,
    "cover identity must stay on the measured safe inset with one avatar/text group",
)
require(
    ".frame(maxWidth: .infinity, alignment: .leading)" in cover
    and ".frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)"
    in cover
    and 'Label(Tr("换封面"), systemImage: "camera.fill")' in cover,
    "profile identity and the edit control must occupy separate corners",
)
require(
    ".fill(Color.dyn(0xFFFFFF, 0x000000).opacity(0.62))" not in cover
    and ".white.opacity(0.86)" in cover
    and "Color.black.opacity(0.58)" in cover,
    "the signature must rely on an editorial scrim instead of a white text card",
)
require(
    "python3 tools/verify-moment-cover-design.py" in WORKFLOW,
    "moment cover design regression must run in the iOS gate",
)

print("moment-cover-design: passed")
