#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DISCOVER = (ROOT / "Sources" / "DiscoverView.swift").read_text(encoding="utf-8")
BOTTOM = (ROOT / "Sources" / "BottomSheetSystem.swift").read_text(encoding="utf-8")
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
    "size: L.coverAvatar" in cover
    and "radius: 8" in cover
    and ".padding(.trailing, 16)" in cover
    and ".offset(y: 21)" in cover
    and ".padding(.bottom, 24)" in cover,
    "cover identity must match the 11/21 lower-right placement",
)
require(
    ".frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)"
    in cover
    and ".frame(width: 88, height: 32)" in cover
    and ".frame(width: 112, height: 56)" in cover
    and ".frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)"
    in cover,
    "profile identity and cover edit control must match their 11/21 edges",
)
require(
    ".fill(Color.dyn(0xFFFFFF, 0x000000).opacity(0.62))" in cover
    and "RoundedRectangle(cornerRadius: 6, style: .continuous)" in cover
    and "Color.black.opacity(0.62)" in cover,
    "the signature and edit control must use the 11/21 material",
)
require(
    "let topOverdraw = max(0, L.safeTop)" in cover
    and "let bottomOverdraw: CGFloat = 2" in cover
    and "let visualHeight = L.coverH + extra + momentProfileFooterHeight\n            + topOverdraw + bottomOverdraw" in cover
    and ".offset(y: -topOverdraw)" in cover,
    "cover artwork must fill the complete moments header without page-colour strips",
)
require(
    "struct BottomChoiceSheet: View" in BOTTOM
    and "sheet(item: $coverSheet)" in DISCOVER
    and "private func queueCoverSheet" in DISCOVER
    and "case .crop(let img):" in DISCOVER
    and "BottomChoiceSheet(" in DISCOVER
    and ".height(BottomChoiceSheet.preferredHeight(itemCount: 2))" in DISCOVER
    and ".presentationDetents([.fraction(0.78), .large])" in DISCOVER
    and "confirmationDialog(Tr(\"更换相册封面\")" not in DISCOVER,
    "cover source selection and crop confirmation must rise from the bottom like WeChat",
)
require(
    DISCOVER.count(".highPriorityGesture(\n") >= 2
    and DISCOVER.count("TapGesture().onEnded { coverSheet = .source }") >= 2
    and ".zIndex(20)" in cover,
    "the empty and existing cover edit buttons must win hit testing over the cover gesture layer",
)
require(
    "python3 tools/verify-moment-cover-design.py" in WORKFLOW,
    "moment cover design regression must run in the iOS gate",
)

print("moment-cover-design: passed")
