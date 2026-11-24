#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
FEED = (ROOT / "Sources" / "FeedView.swift").read_text(encoding="utf-8")
PLAYER = (ROOT / "Sources" / "FeedPlayerView.swift").read_text(encoding="utf-8")
WORKS = (ROOT / "Sources" / "MiscPages.swift").read_text(encoding="utf-8")
MEDIA = (ROOT / "Sources" / "ChatMediaBubbles.swift").read_text(encoding="utf-8")
PIP = (ROOT / "Sources" / "PiPPlayer.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("video interaction verification failed: " + message)


require(
    "private func commentOverlay(_ item: FeedItem)" in FEED
    and "videoScale: commentFor?.id == row.item.id" in FEED
    and "commentsExpanded ? 0.56 : 0.72" in FEED
    and "commentsExpanded.toggle()" in FEED
    and "DragGesture(minimumDistance: 12)" in FEED,
    "comments must expand and collapse while the video scales TikTok-style",
)
require(
    "private func commentOverlay" in FEED
    and "closeComments()" in FEED
    and "arrow.up.left.and.arrow.down.right" in FEED
    and 'Button { sendComment(item) }' in FEED,
    "comments need explicit expand/collapse controls, gestures and a working composer",
)
require(
    ".font(.system(size: 29, weight: .semibold))" in FEED
    and ".font(.system(size: 29, weight: .semibold))" in PLAYER
    and "private var seriesTitle: String" in FEED
    and "private var progressTime: String" in FEED
    and "onPickEpisode()" in FEED,
    "right rail and progress bar must match TikTok hierarchy and expose series selection",
)
require(
    "private func tile(_ w: FeedItem)" in WORKS
    and ".aspectRatio(3.0 / 4.0" in WORKS
    and "FeedWorkThumbnail(item: w)" in WORKS
    and "Image(systemName: \"heart.fill\")" in WORKS,
    "works page must keep a TikTok-style cover preview grid",
)
require(
    "python3 tools/verify-video-interactions.py" in WORKFLOW,
    "video interaction regression must run in the iOS gate",
)
require(
    "func reset()" in PIP
    and "guard layer?.player?.currentItem?.status == .readyToPlay else { return }" in PIP
    and "pip.reset()" in MEDIA,
    "chat video PiP must never open before a frame is ready and must stop on dismissal",
)
require(
    "var previews: [UIImage] = []" in MEDIA
    and "MultiImageMosaic.containerSize(" in MEDIA
    and "MultiImageMosaic.frames(" in MEDIA
    and "SendingFileBubble" in MEDIA
    and ".overlay(alignment: .bottom) {" in MEDIA
    and "uploadProgressFooter" in MEDIA
    and "RoundedRectangle(cornerRadius: 14, style: .continuous)" in MEDIA
    and "private func uploadingRow<Content: View>" in (
        ROOT / "Sources" / "ChatDetailView.swift"
    ).read_text(encoding="utf-8")
    and "Avatar(\n                path: app.me?.avatarPath" in (
        ROOT / "Sources" / "ChatDetailView.swift"
    ).read_text(encoding="utf-8"),
    "pending media needs real phase progress and the self avatar, while files use a standalone card",
)

print("video-interactions: passed")
