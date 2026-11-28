#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHAT = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")
MEDIA = (ROOT / "Sources" / "ChatMediaBubbles.swift").read_text(encoding="utf-8")
API = (ROOT / "Sources" / "API.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)
VIDEO_BUBBLE = MEDIA.split("struct SendingVideoBubble: View", 1)[1].split(
    "struct SendingFileBubble: View", 1
)[0]
VIDEO_SEND = CHAT.split("case .video(let url, let preview):", 1)[1].split(
    "case .live(", 1
)[0]


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("local-first media verification failed: " + message)


require(
    "var result = API.directUploadBases" in API
    and "if !result.contains(base)" in API
    and "result.append(base)" in API,
    "uploads must try the direct origin before the slower public ingress",
)
require(
    "struct PendingMediaPayload: Hashable" in CHAT
    and "private func enqueueOptimisticMedia(" in CHAT
    and "pendingMediaPreviews[id] = images" in CHAT
    and "private func startPendingMediaSend(" in CHAT
    and "outbox.first(where: { !$0.sending })" in CHAT
    and "private func sendPendingMedia(" in CHAT
    and "API.shared.uploadPreparedImageForSend(" in CHAT
    and "seedLocalImage(url, image, data: data)" in CHAT
    and "clientId: pending.id" in CHAT
    and "// 文件 URL 在安全作用域内直接流式上传，不在发送前复制整份文件。" in CHAT
    and "var uploadURL = url" in CHAT
    and "for (index, u) in urls.enumerated()" in CHAT
    and "for (index, u) in stagedURLs.enumerated()" not in CHAT,
    "images must enter the local outbox immediately while their staged files upload in the background",
)
require(
    "private func confirmedSentMessage(_ message: Message?, kind: String) throws -> Message" in CHAT
    and CHAT.count("confirmedSentMessage(") >= 3
    and "guard let message else" in CHAT
    and "服务器没有确认这条媒体消息" in CHAT
    and "try? await API.shared.send" not in CHAT,
    "the local media row may be replaced only after the server confirms a message id",
)
require(
    "private func pendingMediaBubble(" in CHAT
    and "PendingMediaPayload(json: p.content)" in CHAT
    and "SendingVideoBubble(\n            cover: images.first" in CHAT
    and "previews: images" in CHAT
    and "pendingMediaProgress[pending.id]" in CHAT
    and "MultiImageMosaic.frames(" in MEDIA,
    "the local image or mosaic must render inside the real outbox row while upload continues",
)
require(
    "Color.black.opacity(0.42)" not in VIDEO_BUBBLE
    and "100))%" not in VIDEO_BUBBLE
    and ".frame(width: 24, height: 24)" in VIDEO_BUBBLE
    and ".frame(width: 17, height: 17)" in VIDEO_BUBBLE,
    "upload state must be a small corner ring instead of a blocking dark overlay",
)
require(
    "private var playableURL: URL?" in MEDIA
    and "LocalStore.localURL(path)" in MEDIA
    and "return local" in MEDIA
    and "private func enqueueOptimisticVideo(" in CHAT
    and "kind: \"video\"" in CHAT
    and "localURL: videoURL" in CHAT
    and "LocalStore.keepOriginal(remote, from: file)" in CHAT
    and "var localURL: URL? = nil" in VIDEO_BUBBLE
    and "if let localURL { onOpen?(localURL) }" in VIDEO_BUBBLE,
    "a video must be locally playable immediately after send and while its upload row is visible",
)
require(
    "let stable = ImageCacheKey.stablePath(path)" in CHAT
    and "ImageStore.shared.put(path, image)" in CHAT
    and "ImageStore.shared.put(stable, image)" in CHAT
    and "ImageStore.shared.diskWrite(stable, data)" in CHAT
    and "LocalStore.keep(stable, data: data)" in CHAT,
    "a sent image must be indexed under both its exact and stable cache keys for immediate viewing",
)
require(
    "DispatchQueue.main.asyncAfter(deadline: .now() + 0.24)" not in CHAT
    and "filePreview = FilePreviewData(" in CHAT
    and "local: urls[0]" in CHAT
    and "for (index, u) in urls.enumerated()" in CHAT
    and "await uploadAndSendFile(u, transfer: transfer)" in CHAT,
    "file preview must open from the original local URL while bytes stream directly",
)
require(
    "python3 tools/verify-local-first-media.py" in WORKFLOW,
    "local-first media regression must run in the iOS gate",
)

print("local-first-media: passed")
