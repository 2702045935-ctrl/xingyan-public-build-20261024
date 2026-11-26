#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CORE = (ROOT / "Sources" / "Core.swift").read_text(encoding="utf-8")
MEDIA = (ROOT / "Sources" / "ChatMediaBubbles.swift").read_text(encoding="utf-8")
CHAT = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("sent media instant verification failed: " + message)


require(
    "let localBytes: Data? = await Task.detached" in CORE
    and "LocalStore.read(requestedPath)" in CORE
    and CORE.index("LocalStore.read(requestedPath)")
        < CORE.index("ImageStore.shared.diskRead(ImageCacheKey.stablePath(requestedKey))")
        < CORE.index("remote = try await API.shared.imageData(url)"),
    "images must resolve an already saved local file before disk-cache and network fallback",
)
require(
    "private func localOrRemoteMediaURL(_ path: String) -> URL?" in MEDIA
    and "localOrRemoteMediaURL(info.url)" in MEDIA
    and "localOrRemoteMediaURL(info.video)" in MEDIA
    and "VideoForwardPicker(link: sourceLink, videoContent: forwardContent)" in MEDIA
    and "sourceRemoteURL?.absoluteString ?? url.absoluteString" in MEDIA,
    "video and Live Photo bubbles must open their local file immediately when available",
)
require(
    "seedLocalImage(url, img, data: up.data)" in CHAT
    and "LocalStore.keepOriginal(up, from: file)" in CHAT
    and "LocalStore.keepOriginal(vurl, from: file)" in CHAT,
    "the send path must keep image, video, and Live Photo media on disk before appending messages",
)

print("sent-media-instant: passed")
