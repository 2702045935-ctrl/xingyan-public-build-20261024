#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
KERNEL = (ROOT / "server" / "lib" / "video-recommendation.js").read_text(
    encoding="utf-8"
)
SERVER = (ROOT / "server" / "server.js").read_text(encoding="utf-8")
API = (ROOT / "Sources" / "API.swift").read_text(encoding="utf-8")
FEED = (ROOT / "Sources" / "FeedView.swift").read_text(encoding="utf-8")
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
    and "VideoKernelTelemetry.shared.complete(item.id)" in FEED
    and "VideoKernelTelemetry.shared.finish(item.id)" in FEED,
    "active video lifecycle must emit impression, watch time, completion and skip signals",
)
require(
    "preload: row.offset == 1" in FEED
    and "private func prewarm()" in FEED
    and "guard !active, player == nil" in FEED
    and "let hls = item.hls, !hls.isEmpty" in FEED,
    "only the next HLS item may be prewarmed, paused and failure-isolated",
)
require(
    "let path = hls.isEmpty ? mp4 : hls" in FEED
    and "viaDownload: !streaming" in FEED
    and "VideoKernelTelemetry.shared.event(\"first_frame\"" in FEED
    and "VideoKernelTelemetry.shared.event(\"playback_error\"" in FEED,
    "HLS must be preferred for first-frame latency with MP4 fallback and playback metrics",
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
