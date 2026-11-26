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
    and "Text(prefix).foregroundColor(Color(.systemRed))" in CHATS
    and "Text(content).foregroundColor(ChatListVisual.previewInk)" in CHATS
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
    "python3 tools/verify-preview-semantics.py" in WORKFLOW,
    "conversation preview semantics regression must run in the iOS gate",
)

print("preview-semantics: passed")
