#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHATS = (ROOT / "Sources" / "ChatsView.swift").read_text(encoding="utf-8")
ROW = (ROOT / "Sources" / "NativeChatRowCell.swift").read_text(encoding="utf-8")
SERVER = (ROOT / "server" / "server.js").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("preview semantics verification failed: " + message)


require(
    'sessionCopy(zh: "[草稿] ", en: "[Draft] ", ru: "[Черновик] ")' in CHATS,
    "draft previews must use the WeChat-style bracketed prefix in both list implementations",
)
require(
    "if let prefix = draftPrefixes.first(where: { preview.hasPrefix($0) })" in CHATS
    and "Text(prefix).foregroundColor(ChatListVisual.previewAccentInk)" in CHATS
    and "Text(content).foregroundColor(ChatListVisual.conversationPreviewInk)" in CHATS
    and "let draftRegex = try! NSRegularExpression" in ROW,
    "only the draft tag should be red while the draft body stays neutral",
)
require(
    "private static func previewTokenColor" in ROW
    and "private static func previewKindColor" in ROW
    and "return nil\n    }\n\n    private static func previewKindColor" in ROW
    and "return nil\n    }\n\n    private func setupViews" in ROW,
    "media and file tokens in the native conversation row must stay neutral instead of being rainbow-colored",
)
require(
    "NativeChatRowMetrics.font(14," in ROW
    and "previewLabel.font = .systemFont(ofSize: 14, weight: .regular)" in ROW
    and ".font(pfStyled(size: 14," in CHATS
    and "let previewColor = UIColor(hex: isDark ? 0xAEAEB2 : 0x626B66)" in CHATS
    and "static let conversationPreviewInk = Color.dyn(0x626B66, 0xAEAEB2)" in CHATS,
    "conversation previews must use the Apple Messages neutral-gray hierarchy",
)
require(
    "private static let previewAccentInk = UIColor(hex: 0xFA5151)" in ROW
    and "static let previewAccentInk = Color.dyn(0xFA5151, 0xFA5151)" in CHATS
    and "foregroundColor: Self.previewAccentInk" in ROW,
    "mention and draft prefixes must use WeChat's red without tinting the body",
)
require(
    "const clean = path.basename(name.split('?')[0] || '').trim();" in SERVER
    and "return clean ? '[文件] ' + previewTextSlice(clean, 30) : '[文件]';" in SERVER,
    "file previews must use [文件] followed by the visible filename",
)
require(
    "case 'image': return '[图片]'" in SERVER
    and "case 'video': return '[视频]'" in SERVER,
    "image and video previews must remain canonical WeChat tags",
)
require(
    "private func looksLikeStructuredPayload" in CHATS
    and "JSONSerialization.jsonObject" in CHATS
    and 'value.hasPrefix("[")' not in CHATS,
    "bracketed preview labels must not be mistaken for structured JSON payloads",
)
for token in ("[文件]", "[文章]", "[名片]", "[消息已撤回]"):
    require(token in CHATS, "special preview label is missing: " + token)
require(
    'preview.contains("发送失败")' in CHATS
    and 'preview.localizedCaseInsensitiveContains("failed to send")' in CHATS,
    "failed-send previews must use the accent color in both row implementations",
)
require(
    "python3 tools/verify-preview-semantics.py" in WORKFLOW,
    "conversation preview semantics regression must run in the iOS gate",
)

print("preview-semantics: passed")
