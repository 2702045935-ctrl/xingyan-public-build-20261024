#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SHARE = (ROOT / "Sources" / "ShareSheet.swift").read_text(encoding="utf-8")
VIDEO = (ROOT / "Sources" / "VideoShareSheet.swift").read_text(encoding="utf-8")
MALL = (ROOT / "Sources" / "MallDeep.swift").read_text(encoding="utf-8")
PLIST = (ROOT / "Info.plist").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("share sheet verification failed: " + message)


require(
    "struct ShareSheet: UIViewControllerRepresentable" not in SHARE,
    "the default iOS activity controller must not remain the public share UI",
)
require(
    "struct ShareSheet: View" in SHARE,
    "the shared outbound sheet must be a custom SwiftUI page",
)
for token in ("分享到", "SharePreviewCard", "ShareActionTile", "系统分享", "取消"):
    require(token in SHARE, f"shared QQ-style hierarchy is missing {token}")
require(
    "private var actionGrid" in SHARE
    and "ShareActionRow" not in SHARE
    and "LazyVGrid(" in SHARE
    and "count: 4" in SHARE
    and "ShareActionTile(\n                        title: copied" in SHARE
    and "static var accent: Color { Color.dyn(0x0099FF, 0x4CB8FF) }" in SHARE
    and "Color(hex: 0xFF2442)" not in SHARE,
    "the primary share sheet must use QQ's preview and four-column utility icon grid",
)
require(
    "UIActivityViewController(activityItems: items" in SHARE,
    "system apps must remain available through the custom More action",
)
require(
    "SharePreviewCard" in VIDEO and "ShareActionTile" in VIDEO,
    "video sharing must use the shared preview and action hierarchy",
)
require(
    "enum ShareBrand" in SHARE
    and "struct ShareBrandIcon" in SHARE
    and "struct ShareBrandRail" in SHARE
    and "ShareBrandAction.open" in SHARE,
    "share surfaces must expose dedicated branded app actions",
)
for scheme in ("weixin", "mqq", "xhsdiscover", "snssdk1128"):
    require(scheme + "://" in SHARE,
            "missing third-party share scheme: " + scheme)
    require("<string>" + scheme + "</string>" in PLIST,
            "share scheme must be declared in LSApplicationQueriesSchemes: " + scheme)
BRAND_ICON = SHARE[SHARE.index("struct ShareBrandIcon"):SHARE.index("struct ShareBrandRail")]
require(
    "ShareBrandArtwork.wechat" in BRAND_ICON
    and "ShareBrandArtwork.qq" in BRAND_ICON
    and "ShareBrandArtwork.xiaohongshu" in BRAND_ICON
    and BRAND_ICON.count("ShareBrandArtwork.douyin") == 3
    and "Image(systemName: \"music.note\")" not in BRAND_ICON,
    "share brands must use their bundled vector artwork, not generic symbols",
)
require(
    "ShareBrandRail" in VIDEO and "ShareBrandRail" in MALL,
    "video and mall sharing must expose the same branded app row",
)
require(
    "SharePreviewCard" in MALL and "ShareActionTile" in MALL,
    "mall product sharing must use the shared preview and action hierarchy",
)
require(
    "return readableShareText(text)" in SHARE
    and "fetchedLinkTitle ?? Tr(\"网页内容\")" in SHARE
    and "private func loadLinkMetadata() async" in SHARE
    and "og:title" in SHARE
    and "linkTitle(from: html)" in SHARE
    and "URLSession.shared.data(for: request)" in SHARE
    and "raw.lowercased().hasPrefix(\"http\")" in SHARE,
    "share previews must use page metadata and never print a raw URL",
)
require(
    "static func pageBackdrop(_ scheme: ColorScheme) -> some View" in SHARE
    and ".fill(C.floatingSurface)" in SHARE
    and "shareSheetTranslucentBackground()" in SHARE
    and "presentationBackground(.clear)" in SHARE
    and "ShareSheetTheme.pageBackdrop(scheme)" in SHARE
    and "ShareSheetTheme.pageBackdrop(scheme)" in VIDEO
    and "ShareSheetTheme.pageBackdrop(scheme)" in MALL,
    "every share sheet must use the shared opaque surface",
)
require(
    "presentationDragIndicator(.visible)" in SHARE
    and "presentationCornerRadius(30)" in SHARE
    and "HStack(alignment: .top, spacing: 0)" in SHARE
    and ".padding(.horizontal, 6)" in SHARE
    and "RoundedRectangle(cornerRadius: 18, style: .continuous)" in SHARE
    and "Text(Tr(\"分享到\"))\n                .font(pf(17, .semibold))" in SHARE
    and "pf(20, .bold)" not in SHARE,
    "share sheet layout must use QQ's compact app grid and utility hierarchy",
)
require(
    ".ddLight()" not in MALL[MALL.index("struct DDShareSheet"):MALL.index("struct DDOrderDetailView")],
    "the mall share sheet must support the app's dark appearance",
)

print("share-sheets: passed")
