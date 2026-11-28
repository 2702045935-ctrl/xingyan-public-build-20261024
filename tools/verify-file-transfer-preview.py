#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHAT = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")
CORE = (ROOT / "Sources" / "Core.swift").read_text(encoding="utf-8")
MEDIA = (ROOT / "Sources" / "ChatMediaBubbles.swift").read_text(encoding="utf-8")
NAV = (ROOT / "Sources" / "NavGlass.swift").read_text(encoding="utf-8")
EXTERNAL = (ROOT / "Sources" / "ExternalFileInbox.swift").read_text(encoding="utf-8")
RULES = (ROOT / "Sources" / "FileUploadRules.swift").read_text(encoding="utf-8")
AI_PAGE = (ROOT / "Sources" / "AIPage.swift").read_text(encoding="utf-8")
AI_WORKSPACE = (ROOT / "Sources" / "AIWorkspaceView.swift").read_text(encoding="utf-8")
SENDING_FILE = MEDIA.split("struct SendingFileBubble: View", 1)[1].split(
    "private func byteText", 1
)[0]


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
require(
    "enum FileUploadUX" in RULES
    and "struct FileUploadProgressBar" in RULES
    and "static let maxBytes = 100 * 1024 * 1024" in RULES
    and "FileUploadUX.uploading(value)" in SENDING_FILE
    and "FileUploadProgressBar(progress: value" in SENDING_FILE
    and "FileUploadUX.uploading(transfer.progress)" in CHAT
    and "FileUploadProgressBar(progress: transfer.progress" in CHAT
    and "FileUploadUX.batchUploading" in EXTERNAL
    and "FileUploadProgressBar(progress: transferFraction" in EXTERNAL
    and "服务器处理中" not in SENDING_FILE,
    "all file upload surfaces must share one QQ-style progress and status system",
)
require(
    "文件发送失败" not in AI_PAGE
    and "文件发送失败" not in AI_WORKSPACE
    and ".alert(alert" not in EXTERNAL
    and "operationError" in EXTERNAL
    and "FileUploadUX.failure" in CHAT,
    "file failures must stay in the upload surface instead of raising generic failure dialogs",
)

print("file-transfer-preview: passed")
