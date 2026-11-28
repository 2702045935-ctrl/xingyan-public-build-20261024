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
adjust_start = DISCOVER.index("struct CoverAdjustSheet")
adjust_end = DISCOVER.index("struct MomentGridDrop", adjust_start)
adjust = DISCOVER[adjust_start:adjust_end]

require(
    "size: L.coverAvatar" in cover
    and "radius: 16" in cover
    and ".padding(.trailing, 16)" in cover
    and ".padding(.bottom, 8)" in cover
    and ".padding(.bottom, 24)" in cover,
    "cover identity must remain in the original lower-right placement",
)
require(
    ".frame(maxWidth: .infinity, alignment: .trailing)" in cover
    and ".frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)"
    in cover
    and 'Label(Tr("换封面"), systemImage: "camera.fill")' in cover,
    "profile identity and the edit control must keep their separate original edges",
)
require(
    ".fill(Color.dyn(0xFFFFFF, 0x000000).opacity(0.62))" not in cover
    and ".white.opacity(0.90)" in cover
    and "NativeMediaGlassSurface(" in cover
    and "Color.black.opacity(0.24)" in cover
    and "Color.white.opacity(0.14)" in cover,
    "cover identity and edit controls must use restrained native material",
)
require(
    "let topOverdraw = max(0, L.safeTop)" in cover
    and "let visualHeight = L.coverH + extra + topOverdraw" in cover
    and ".offset(y: -topOverdraw)" in cover,
    "cover artwork must overdraw the top safe area so no page-colour strip remains",
)
require(
    "python3 tools/verify-moment-cover-design.py" in WORKFLOW,
    "moment cover design regression must run in the iOS gate",
)
require(
    "GeometryReader { proxy in" in adjust
    and "private func cropCanvas" in adjust
    and "private var cropGrid" in adjust
    and "private func clampedOffset" in adjust
    and ".frame(width: crop.width, height: crop.height)" in adjust
    and "offset = clampedOffset(next, scale: scale, crop: crop)" in adjust
    and "NavBar(title: Tr(\"拖动调整\")" not in adjust,
    "cover adjustment must be rebuilt as a bounded immersive canvas",
)
require(
    "NativeMediaGlassSurface(" in adjust
    and "shape: AnyShape(Rectangle())" in adjust
    and "interactive: true" in adjust
    and "RoundedRectangle(cornerRadius: 24, style: .continuous)" in adjust,
    "immersive cover controls and backdrop must use native system material",
)

print("moment-cover-design: passed")
