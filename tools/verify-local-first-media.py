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
    "sendingPreview = img\n            sendingPreviews = [img]" in CHAT
    and "sendingPreview = list.first\n            sendingPreviews = list" in CHAT
    and 'let uploadGroup = "multi-" + UUID().uuidString' in CHAT
    and "uploadGroup: uploadGroup" in CHAT
    and 'sendingMedia = Tr("图片上传中…") + " \\(state.completed)/\\(list.count)"' not in CHAT
    and "let upstream = try await API.shared.uploadImageForSend(" in CHAT
    and "seedLocalImage(url, img, data: upstream.data)" in CHAT
    and "// 文件 URL 在安全作用域内直接流式上传，不在发送前复制整份文件。" in CHAT
    and "var uploadURL = url" in CHAT
    and "for (index, u) in urls.enumerated()" in CHAT
    and "for (index, u) in stagedURLs.enumerated()" not in CHAT,
    "multi-image sends must use one logical upload group and no per-file upload counter",
)
require(
    "private func confirmedSentMessage(_ message: Message?, kind: String) throws -> Message" in CHAT
    and CHAT.count("confirmedSentMessage(") >= 7
    and "try? await API.shared.send" not in CHAT,
    "media may clear its local uploading state only after the server confirms a message id",
)
require(
    "sendingPreview = img\n            sendingPreviews = [img]" in CHAT
    and "sendingPreview = list.first\n            sendingPreviews = list" in CHAT
    and "sendingVideoBubble" not in CHAT
    and "SendingVideoBubble(cover: sendingPreview," in CHAT
    and "previews: sendingPreviews" in CHAT
    and "MultiImageMosaic.frames(" in MEDIA,
    "the real local image or mosaic must appear immediately while upload continues",
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
    and "localURL: sendingVideoURL" in CHAT
    and "sendingVideoURL = url" in VIDEO_SEND
    and "sendingVideoURL = nil" in VIDEO_SEND
    and "var localURL: URL? = nil" in VIDEO_BUBBLE
    and "if let localURL { onOpen?(localURL) }" in VIDEO_BUBBLE
    and VIDEO_SEND.index("LocalStore.keepOriginal(up, from: file)")
    < VIDEO_SEND.index("API.shared.send("),
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
