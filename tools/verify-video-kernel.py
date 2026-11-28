#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
KERNEL = (ROOT / "server" / "lib" / "video-recommendation.js").read_text(
    encoding="utf-8"
)
SERVER = (ROOT / "server" / "server.js").read_text(encoding="utf-8")
API = (ROOT / "Sources" / "API.swift").read_text(encoding="utf-8")
FEED = (ROOT / "Sources" / "FeedView.swift").read_text(encoding="utf-8")
PLAYER = (ROOT / "Sources" / "FeedPlayerView.swift").read_text(encoding="utf-8")
KERNEL_IOS = (ROOT / "Sources" / "VideoPlaybackKernel.swift").read_text(
    encoding="utf-8"
)
STREAM = (ROOT / "Sources" / "StreamPlayback.swift").read_text(encoding="utf-8")
TELEMETRY = (ROOT / "Sources" / "VideoKernelTelemetry.swift").read_text(
    encoding="utf-8"
)
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("video kernel verification failed: " + message)


require(
    "class VideoRecommendationKernel" in KERNEL
    and "preferenceModel(" in KERNEL
    and "itemFeedback(" in KERNEL
    and "sources.includes('explore')" in KERNEL,
    "recommendation kernel must expose preference, feedback and exploration stages",
)
require(
    "videoRecommendationKernel.rank({" in SERVER
    and "回退旧排序" in SERVER
    and "parts[0] === 'feed' && parts[1] === 'events'" in SERVER,
    "feed ranking must have a fail-open fallback and a feedback endpoint",
)
require(
    "func feedEvents(_ events: [VideoKernelFeedbackEvent]) async -> Bool" in API,
    "client API must submit video feedback events",
)
require(
    "VideoKernelTelemetry.shared.begin(item.id)" in FEED
    and "VideoKernelTelemetry.shared.update(item.id" in FEED
    and "VideoKernelTelemetry.shared.complete(entry.item.id)" in KERNEL_IOS
    and "VideoKernelTelemetry.shared.finish(item.id)" in FEED,
    "active video lifecycle must emit impression, watch time, completion and skip signals",
)
require(
    "final class VideoPlaybackPolicy" in KERNEL_IOS
    and "var playerLimit: Int {" in KERNEL_IOS
    and "min(reducesWork ? 2 : 4, hardwarePlayerLimit)" in KERNEL_IOS
    and "var lookAhead: Int {" in KERNEL_IOS
    and "min(reducesWork ? 1 : 2, hardwareLookAhead)" in KERNEL_IOS
    and "hardwarePlayerLimit" in KERNEL_IOS,
    "the playback kernel needs bounded adaptive hot-player and look-ahead limits",
)
require(
    "let preferOriginal = item.mine == true && isRecentUpload(item.createdAt)" in KERNEL_IOS
    and "if preferOriginal, let videoURL" in KERNEL_IOS
    and "if let hlsURL" in KERNEL_IOS
    and "if !preferOriginal, let videoURL" in KERNEL_IOS
    and KERNEL_IOS.index("if let hlsURL") < KERNEL_IOS.index("if !preferOriginal, let videoURL"),
    "newly published owned videos must play MP4 first while normal videos keep HLS first",
)
require(
    "entry.player.preroll(atRate: 1.0)" in KERNEL_IOS
    and ".AVPlayerItemPlaybackStalled" in KERNEL_IOS
    and "private func recover(_ entry: Entry, reason: String)" in KERNEL_IOS
    and "首帧超时" in KERNEL_IOS
    and "播放停滞" in KERNEL_IOS,
    "the kernel must preroll, detect stalls, and recover from first-frame timeouts",
)
require(
    "PlayerPool.shared.focus(items: items, index: index)" in PLAYER
    and "PlayerPool.shared.focus(items: items, index: i)" in FEED
    and "@ObservedObject private var playerPool = PlayerPool.shared" in FEED,
    "main-feed and full-screen playback must share the bounded playback pool",
)
require(
    "StreamPlay.cancel(old)" in KERNEL_IOS
    and "loader.cancelAll()" in STREAM
    and "release(loader)" in STREAM
    and "while keepOrder.count > 32" in STREAM,
    "stream loaders must be released and retained under a hard upper bound",
)
require(
    "VideoKernelTelemetry.shared.event(\"first_frame\"" in KERNEL_IOS
    and "VideoKernelTelemetry.shared.event(\"playback_error\"" in KERNEL_IOS,
    "playback lifecycle must report first-frame and recovery failures",
)
require(
    "private var pending: [VideoKernelFeedbackEvent] = []" in TELEMETRY
    and "pending.count > 240" in TELEMETRY
    and "pending.insert(contentsOf: batch, at: 0)" in TELEMETRY,
    "telemetry must remain bounded and retry safely without blocking playback",
)
require(
    "node server/test/video-recommendation.test.js" in WORKFLOW,
    "video recommendation regression must run in the iOS gate",
)

print("video-kernel: passed")
