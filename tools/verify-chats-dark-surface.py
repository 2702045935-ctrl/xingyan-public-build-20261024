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
    "chatsIsDark\n            ? Color(hex: 0x0A0A0A)\n            : UIConfig.fixedLight(\"chatsPageBg\", 0xFFFFFF)" in CHATS
    and "if isDark { return Color(hex: 0x0A0A0A) }" in CHATS
    and "let rowBg: UIColor = isDark ? UIColor(hex: 0x0A0A0A) : UIColor.white" in CHATS,
    "chat canvas must resolve explicit dark and light surfaces without environment delay",
)
require(
    "showsDivider: true" in CHATS
    and "? UIColor(hex: 0x232326)" in CHATS
    and "dividerColor: isDark\n                ? UIColor(hex: 0x232326)" in CHATS
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
    "table.topEdgeEffect.style = .hard" in NATIVE_LIST
    and "table.topEdgeEffect.isHidden = true" in NATIVE_LIST
    and "controller.tableView.topEdgeEffect.isHidden = true" in NATIVE_LIST
    and "dark: chatsIsDark" in CHATS,
    "the chat surface must disable the flashing system edge line in every theme",
)
require(
    "background: chatsPageFill" in CHATS
    and "opacity(scrolled > 0 ? 1 : 0)" in NAV
    and "background ?? (isDark ? C.pageBg" in NAV,
    "scrolled chat content must disappear behind an opaque top chrome",
)
require(
    "previewLabel.attributedText = nil" in ROW
    and "titleLabel.text = nil" in ROW
    and "foreground.layer.isOpaque = opaque" in ROW
    and "contentView.isOpaque = true" in ROW,
    "reused native rows must clear old text and render on an opaque surface",
)
require(
    "? Color(hex: 0x111111)" in CHATS
    and "Color.white.opacity(0.045)" in CHATS
    and "Color(hex: 0x6E7378)" in CHATS
    and ".stroke(chatsSearchBorder, lineWidth: 0.5)" in CHATS,
    "dark search must sit quietly on the near-black canvas instead of using a raised light card",
)
require(
    '"\\(chatsIsDark)-\\(scheme)-\\(Lang.code)' in CHATS
    and "if context.coordinator.dark != dark" in NATIVE_LIST
    and "context.coordinator.refreshVisibleRowsAfterThemeChange()" in NATIVE_LIST
    and "table.cellForRow(at: indexPath) as? NativeChatRowCell" in NATIVE_LIST
    and "cell.configure(configuration)" in NATIVE_LIST
    and "table.reloadRows" not in NATIVE_LIST,
    "native rows must repaint visible cells without entering a table update transaction",
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
    "let previewColor = UIColor(hex: isDark ? 0x74787D : 0x999999)" in CHATS
    and "let timeColor = UIColor(hex: isDark ? 0x55595E : 0xB2B2B2)" in CHATS
    and "static let conversationPreviewInk = Color.dyn(0x999999, 0x74787D)" in CHATS
    and "static let timeInk = Color.dyn(0xB2B2B2, 0x55595E)" in CHATS
    and "let titleColor: UIColor = chat.showsOfficialMark" in CHATS
    and "UIColor(hex: isDark ? 0xEBEBF0 : 0x191919)" in CHATS,
    "chat-list title, preview and time must form the refined dark hierarchy",
)
require(
    "static let avatarSize: CGFloat = 48" in CHATS
    and "static let avatarGap: CGFloat = 13" in CHATS
    and "max(73, (73 + (combinedScale - 1) * 34).rounded())" in ROW
    and "weight: .medium, textStyle: .headline" in ROW,
    "conversation rows must use the tighter WeChat avatar grid and lighter title weight",
)

print("chats-dark-surface: passed")
