#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SIDEBAR = (ROOT / "Sources" / "AccountSidebarView.swift").read_text(encoding="utf-8")
CHATS = (ROOT / "Sources" / "ChatsView.swift").read_text(encoding="utf-8")
MAIN = (ROOT / "Sources" / "MainTab.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("account sidebar verification failed: " + message)


require(
    "static let maxWidth: CGFloat = 320" in SIDEBAR
    and "static let minimumTrailingReveal: CGFloat = 48" in SIDEBAR
    and "static func width(for screenWidth: CGFloat) -> CGFloat" in SIDEBAR
    and "static let cornerRadius: CGFloat = 24" in SIDEBAR
    and "struct AccountSidebarShape: Shape" in SIDEBAR,
    "account sidebar must expose one shared drawer-width calculation",
)
require(
    "static let rowHeight: CGFloat = 52" in SIDEBAR
    and "static let profileHeight: CGFloat = 72" in SIDEBAR
    and "static let avatarSize: CGFloat = 56" in SIDEBAR
    and "sectionTitle(Tr(\"快捷\"))" in SIDEBAR
    and "sectionTitle(Tr(\"管理\"))" in SIDEBAR
    and "private var footer: some View" in SIDEBAR,
    "account sidebar must keep the fixed identity, scrolling actions and fixed footer",
)
require(
    "AccountSidebarOverlay(" in MAIN
    and ".onReceive(NotificationCenter.default.publisher(for: .chrisOpenAccountSidebar))" in MAIN
    and "AccountSidebarMetrics.width(for: proxy.size.width)" in MAIN
    and ".offset(x: showAccountSidebar ? drawerWidth : 0)" in MAIN
    and "NotificationCenter.default.post(\n                        name: .chrisOpenAccountSidebar" in CHATS
    and "showAccounts = true" not in CHATS
    and ".sheet(isPresented: $showAccounts)" not in CHATS,
    "opening the drawer must push the real conversation page to the right",
)
require(
    "isOpen ? dragTranslation : -width - 24" in SIDEBAR
    and "horizontal < -72 || velocity < -520" in SIDEBAR
    and ".simultaneousGesture(" in SIDEBAR
    and ".allowsHitTesting(isOpen)" in SIDEBAR,
    "the drawer must support scrim dismissal and a restrained swipe-close gesture",
)
require(
    "AccountSidebarAvatarRail" not in SIDEBAR
    and "railAccounts" not in SIDEBAR
    and "Color.clear\n                    .ignoresSafeArea()" in SIDEBAR
    and ".offset(x: showAccountSidebar ? drawerWidth : 0)" in MAIN,
    "the exposed trailing edge must be the real conversation page, not a fake avatar rail",
)
require(
    "Color.black.opacity(0.42)" in SIDEBAR
    and "Color.white.opacity(0.62)" in SIDEBAR
    and "private var panelColorGlow: LinearGradient" in SIDEBAR
    and "accent.opacity(0.07)" in SIDEBAR
    and "Color.dyn(0x0F8B65, 0x36CA95)" in SIDEBAR,
    "sidebar material must remain visibly frosted and color-tinted",
)
require(
    ".frame(width: 28, height: 28)" in SIDEBAR
    and "RoundedRectangle(cornerRadius: 7, style: .continuous)" in SIDEBAR
    and "SupportView()" in SIDEBAR
    and "FeedbackView()" not in SIDEBAR,
    "sidebar actions must use system icon tiles and one unified help center",
)
require(
    "struct AccountSidebarPressStyle: ButtonStyle" in SIDEBAR
    and "configuration.isPressed" in SIDEBAR
    and "Color.primary.opacity(" in SIDEBAR
    and "struct AccountSidebarShape: Shape" in SIDEBAR,
    "sidebar material and press states must use the shared restrained surface system",
)
require(
    "python3 tools/verify-account-sidebar.py" in WORKFLOW,
    "the account sidebar regression must run in the iOS gate",
)

print("account-sidebar: passed")
