#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHATS = (ROOT / "Sources" / "ChatsView.swift").read_text(encoding="utf-8")
ROW = (ROOT / "Sources" / "NativeChatRowCell.swift").read_text(encoding="utf-8")
NATIVE_LIST = (ROOT / "Sources" / "NativeChatList.swift").read_text(encoding="utf-8")
NAV = (ROOT / "Sources" / "NavGlass.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("dark chat surface verification failed: " + message)


require(
    "chatsIsDark\n            ? C.pageBg\n            : UIConfig.fixedLight(\"chatsPageBg\", 0xF2F4F1)" in CHATS
    and "chatsIsDark\n            ? C.chatRowBg" in CHATS
    and "let rowBg = isDark ? UIColor.clear : UIColor(hex: 0xFAFBF9)" in CHATS,
    "pure-native dark rows must be transparent over the system page canvas",
)
require(
    "showsDivider: true" in CHATS
    and "dividerColor: isDark\n                ? .separator" in CHATS
    and ".fill(ChatListVisual.rule)" in CHATS
    and ".fill(isDark ? Color.clear : ChatListVisual.rule)" not in CHATS
    and "dividerLeading: CGFloat = 77" in ROW,
    "dark chat rows must use a subtle 77pt structural hairline",
)
require(
    'divider.isHidden = !configuration.showsDivider' in ROW,
    "native row cells must apply the divider visibility configuration",
)
require(
    "table.topEdgeEffect.style = .automatic" in NATIVE_LIST
    and "table.topEdgeEffect.isHidden = true" in NATIVE_LIST
    and "scrollView.topEdgeEffect.isHidden = hidden" in NATIVE_LIST
    and "dark: chatsIsDark" in CHATS,
    "the chat surface must expose the native edge effect only after scrolling",
)
require(
    "NativeTopGlassMask(" in CHATS
    and "active: chatTopScrolled > 0" in CHATS
    and "edgeBlend: true" in CHATS
    and "if #available(iOS 26.0, *), chatsIsDark {" in CHATS
    and "NativeScrollEdgeElementBridge(" in CHATS
    and "NativeFrostedHeaderMaterial(chrome: edgeBlend)" in NAV
    and ".systemChromeMaterialDark" in NAV
    and ".systemChromeMaterialLight" in NAV
    and "Color.white.opacity(0.018)" in NAV
    and ".init(color: .clear, location: 1)" in NAV,
    "the dark conversation chrome must use visible system material with a soft lower edge",
)
require(
    "previewLabel.attributedText = nil" in ROW
    and "titleLabel.text = nil" in ROW
    and "foreground.layer.isOpaque = opaque" in ROW
    and "contentView.isOpaque = true" in ROW,
    "reused native rows must clear old text and render on an opaque surface",
)
require(
    "private let topSheen = UIView()" in ROW
    and "topSheen.backgroundColor = .clear" in ROW
    and "topSheen.isHidden = true" in ROW,
    "the pure-native preview must remove the custom row sheen",
)
require(
    "chatsIsDark\n            ? Color(hex: 0x2A2A2C)" in CHATS
    and "Color.white.opacity(0.04)" in CHATS
    and "Color(hex: 0x8D8D93)" in CHATS
    and ".stroke(chatsSearchBorder, lineWidth: 0.5)" in CHATS,
    "dark search must use the restrained SMS-like raised control tone",
)
require(
    "private struct NativeConversationSearchSurface: UIViewRepresentable" in CHATS
    and "if chatsIsDark {\n                    NativeConversationSearchSurface(" in CHATS
    and "field.isUserInteractionEnabled = false" in CHATS
    and "field.isAccessibilityElement = false" in CHATS
    and "if !chatsIsDark {\n                    RoundedRectangle(cornerRadius: 9" in CHATS,
    "dark chat search must render the native search field while light keeps its prior chrome",
)
require(
    '"\\(chatsIsDark)-\\(scheme)-\\(Lang.code)' in CHATS
    and "if context.coordinator.dark != dark" in NATIVE_LIST
    and "context.coordinator.refreshVisibleRowsAfterThemeChange()" in NATIVE_LIST
    and "let cell = table.cellForRow(at: indexPath)" in NATIVE_LIST
    and "nativeCell.configure(configuration)" in NATIVE_LIST
    and "cell.contentConfiguration = UIHostingConfiguration" in NATIVE_LIST
    and "table.reloadRows" not in NATIVE_LIST,
    "native and hosted rows must repaint together without a table update transaction",
)
require(
    "if snapshot.list.isEmpty {\n                    VStack" not in CHATS
    and "private var chatListEmptyState" in CHATS
    and "private var chatListEmptyTitle" in CHATS
    and "private var chatListEmptyDetail" in CHATS
    and ".background(OrbitTheme.canvas)" not in CHATS,
    "empty and filtered chat lists must stay inside the native list surface",
)
require(
    "let previewColor = isDark ? UIColor.secondaryLabel : UIColor(hex: 0x626B66)" in CHATS
    and "let timeColor = isDark ? UIColor.tertiaryLabel : UIColor(hex: 0x858D88)" in CHATS
    and "? .secondaryLabel" in CHATS
    and "? .tertiaryLabel" in CHATS
    and "let titleColor: UIColor = chat.showsOfficialMark" in CHATS
    and "(isDark ? .label : UIColor(hex: 0x171A18))" in CHATS,
    "pure-native dark rows must use UIKit semantic label colors",
)
require(
    "trait.userInterfaceStyle == .dark" in CHATS
    and "? .label" in CHATS
    and "? .secondaryLabel" in CHATS
    and "? .tertiaryLabel" in CHATS,
    "hosted rows must preserve the native label hierarchy",
)
require(
    "static let avatarSize: CGFloat = 48" in CHATS
    and "static let avatarGap: CGFloat = 12" in CHATS
    and "max(72, (72 + (combinedScale - 1) * 34).rounded())" in ROW
    and "weight: .semibold, textStyle: .headline" in ROW,
    "conversation rows must use the tighter avatar grid and one semibold title weight",
)
require(
    "private enum OfficialRowVisual" in CHATS
    and "Color(hex: 0x1FAE79)" in CHATS
    and "Color(hex: 0x0E805E)" in CHATS
    and "Color(hex: 0x64D2FF)" in CHATS
    and "Color(hex: 0x2E9BEC)" in CHATS
    and "OfficialRowVisual.weatherSun" in CHATS
    and "PayVisual.tint.opacity(0.20)" in CHATS
    and "UIColor(hex: isDark ? 0x42C693 : 0x137D5B)" in CHATS
    and ".foregroundStyle(OfficialAccountVisual.name)\n                                .lineLimit(1)" in CHATS
    and ".foregroundStyle(ChatListVisual.ink)\n                                .lineLimit(1)" in CHATS,
    "official-account rows must use the restrained brand icon and official-name hierarchy",
)

print("chats-dark-surface: passed")
