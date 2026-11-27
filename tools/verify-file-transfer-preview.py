#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHAT = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")
CORE = (ROOT / "Sources" / "Core.swift").read_text(encoding="utf-8")
MEDIA = (ROOT / "Sources" / "ChatMediaBubbles.swift").read_text(encoding="utf-8")
NAV = (ROOT / "Sources" / "NavGlass.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("file transfer preview verification failed: " + message)


require(
    "final class FileTransferState" in CHAT
    and "struct FileTransferProgressCard" in CHAT
    and "var transfer: FileTransferState? = nil" in CHAT
    and "transfer: f.transfer" in CHAT
    and "private func uploadAndSendFile(_ url: URL, transfer: FileTransferState? = nil)"
    in CHAT
    and "transfer.upload(progress: value)" in CHAT,
    "file upload progress must be owned by the preview transfer state",
)
require(
    "filePreview = FilePreviewData(" in CHAT
    and "FileTransferProgressCard(transfer: transfer)" in CHAT
    and "NativeMediaGlassSurface(shape: AnyShape(Rectangle()))" in CHAT,
    "file preview must show the real transfer state and native media controls",
)
require(
    "struct NativeMediaGlassMaterial" in NAV
    and "UIGlassEffect(style: .regular)" in NAV
    and "UIBlurEffect(style: scheme == .dark" in NAV
    and "struct NativeMediaGlassSurface" in NAV,
    "media glass must be a native system component with a native fallback",
)
require(
    "NativeMediaGlassCircleBackground()" in CORE
    and "NativeMediaGlassCircleBackground()" in MEDIA
    and "NativeGlassCircleBackground()" not in CORE
    and "NativeGlassCircleBackground()" not in MEDIA,
    "photo and video viewer controls must use the native media glass component",
)

print("file-transfer-preview: passed")
