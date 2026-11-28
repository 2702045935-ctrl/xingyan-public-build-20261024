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


start = DISCOVER.index("@ViewBuilder\n    private var momentCoverEditControl")
end = DISCOVER.index("private func dayLabel", start)
cover = DISCOVER[start:end]
adjust_start = DISCOVER.index("struct CoverAdjustSheet")
adjust_end = DISCOVER.index("struct MomentGridDrop", adjust_start)
adjust = DISCOVER[adjust_start:adjust_end]

require(
    "size: max(58, L.coverAvatar)" in cover
    and "radius: 20" in cover
    and ".padding(.trailing, 16)" in cover
    and ".padding(.bottom, 8)" in cover
    and "min(300, max(196, L.width - 72))" in cover,
    "cover identity must stay in the original lower-right placement",
)
require(
    ".frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)"
    in cover,
    "cover identity must stay outside the top safe area and remain bottom-right",
)
require(
    ".frame(maxWidth: .infinity, alignment: .trailing)" in cover
    and ".frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)"
    in cover
    and 'Image(systemName: "camera.fill")' in cover
    and 'accessibilityLabel(Tr("换封面"))' in cover,
    "the editorial identity and compact edit control must use separate lower edges",
)
require(
    ".fill(Color.dyn(0xFFFFFF, 0x000000).opacity(0.62))" not in cover
    and 'Text(Tr("生活圈"))' in cover
    and "font(pf(24, .semibold))" in cover
    and ".white.opacity(0.84)" in cover
    and "NativeMediaGlassSurface(" in cover
    and "Circle().fill(Color.black.opacity(0.28))" in cover
    and "Color.white.opacity(0.62)" in cover,
    "the cover must use editorial type hierarchy and one native edit control",
)
require(
    "private var momentCoverScrim: some View" in cover
    and "LinearGradient(" in cover
    and "RadialGradient(" in cover
    and "location: 1" in cover
    and "HarmonyDarkMask(strength: 0.94)" not in cover
    and "HarmonyDarkMask(strength: 0.96)" not in cover,
    "the cover must use one unified cinematic scrim instead of stacked legacy masks",
)
require(
    "frame(width: 1, height: max(44, L.coverAvatar * 0.8))" in cover
    and "frame(width: 42, height: 42)" in cover
    and ".frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)"
    in cover,
    "cover controls and identity must share one intentional bottom composition",
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
    ".fullScreenCover(isPresented: Binding(get: { coverDraft != nil }" in DISCOVER,
    "cover adjustment must use an edge-to-edge full-screen presentation",
)
require(
    "NativeMediaGlassSurface(" in adjust
    and "shape: AnyShape(Rectangle())" in adjust
    and "interactive: true" in adjust
    and "RoundedRectangle(cornerRadius: 24, style: .continuous)" in adjust,
    "immersive cover controls and backdrop must use native system material",
)

print("moment-cover-design: passed")
