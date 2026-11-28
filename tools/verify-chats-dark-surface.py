#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHATS = (ROOT / "Sources" / "ChatsView.swift").read_text(encoding="utf-8")
ROW = (ROOT / "Sources" / "NativeChatRowCell.swift").read_text(encoding="utf-8")
NATIVE_LIST = (ROOT / "Sources" / "NativeChatList.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("dark chat surface verification failed: " + message)


require(
    "chatsIsDark\n            ? C.pageBg\n            : UIConfig.fixedLight(\"chatsPageBg\", 0xF2F4F1)" in CHATS
    and "chatsIsDark\n            ? C.chatRowBg" in CHATS
    and "let rowBg = isDark ? UIColor(C.chatRowBg) : UIColor(hex: 0xFAFBF9)" in CHATS,
    "chat canvas must resolve explicit dark and light surfaces without environment delay",
)
require(
    "showsDivider: true" in CHATS
    and "dividerColor: isDark\n                ? UIColor(hex: 0x242824)" in CHATS
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
    "previewLabel.attributedText = nil" in ROW
    and "titleLabel.text = nil" in ROW
    and "foreground.layer.isOpaque = opaque" in ROW
    and "contentView.isOpaque = true" in ROW,
    "reused native rows must clear old text and render on an opaque surface",
)
require(
    "private let topSheen = UIView()" in ROW
    and "topSheen.isHidden = configuration.isLight" in ROW
    and "UIColor.white.withAlphaComponent(0.016)" in ROW
    and "topSheen.heightAnchor.constraint(equalToConstant: 0.5)" in ROW,
    "dark rows need a restrained top-light finish without changing row backgrounds",
)
require(
    "chatsIsDark\n            ? C.searchBg" in CHATS
    and "Color.white.opacity(0.035)" in CHATS
    and "Color(hex: 0x7F847F)" in CHATS
    and ".stroke(chatsSearchBorder, lineWidth: 0.5)" in CHATS,
    "dark search must sit quietly on the near-black canvas instead of using a raised light card",
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
    "let previewColor = UIColor(hex: isDark ? 0x9FA49F : 0x626B66)" in CHATS
    and "let timeColor = UIColor(hex: isDark ? 0x737873 : 0x858D88)" in CHATS
    and "static let conversationPreviewInk = Color.dyn(0x626B66, 0x9FA49F)" in CHATS
    and "static let timeInk = Color.dyn(0x858D88, 0x737873)" in CHATS
    and "let titleColor: UIColor = chat.showsOfficialMark" in CHATS
    and "UIColor(hex: isDark ? 0xF1F3F0 : 0x171A18)" in CHATS,
    "chat-list title, preview and time must use the softened dark hierarchy",
)
require(
    0xF1F3F0 > 0x9FA49F > 0x737873,
    "dark title, preview and time must remain strictly ordered with time weakest",
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
