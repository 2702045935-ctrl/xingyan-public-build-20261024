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
    "private func stageLocalOutgoingImage(" in CHAT
    and "LocalStore.keep(path, data: data)" in CHAT
    and "private func stageLocalOutgoingFile(" in CHAT
    and "LocalStore.keepOriginal(path, from: source)" in CHAT
    and CHAT.count("stageLocalOutgoingImage(") >= 4
    and CHAT.count("stageLocalOutgoingFile(") >= 3,
    "images, live photos, videos and files must be persisted locally before remote completion",
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
    "DispatchQueue.main.asyncAfter(deadline: .now() + 0.24)" not in CHAT
    and "filePreview = FilePreviewData(" in CHAT
    and "await stageLocalOutgoingFile(u)" in CHAT,
    "file preview must open immediately from local content",
)
require(
    "python3 tools/verify-local-first-media.py" in WORKFLOW,
    "local-first media regression must run in the iOS gate",
)

print("local-first-media: passed")
