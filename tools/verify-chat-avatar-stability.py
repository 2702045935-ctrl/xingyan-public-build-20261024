#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "Sources" / "NativeChatRowCell.swift").read_text(encoding="utf-8")
CORE = (ROOT / "Sources" / "Core.swift").read_text(encoding="utf-8")
APP = (ROOT / "Sources" / "App.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("chat avatar stability verification failed: " + message)


require(
    "avatarView.invalidate()" in SOURCE
    and "avatarView.reset()" not in SOURCE,
    "cell reuse must invalidate requests without clearing visible avatars",
)
require(
    "private var sourceSignature" in SOURCE
    and "let sourceChanged = nextSourceSignature != sourceSignature" in SOURCE
    and "if sourceChanged {\n            sourceSignature = nextSourceSignature\n            token = UUID()" in SOURCE,
    "presence and music updates must not replace the avatar request token",
)
require(
    "private var tilePaths" in SOURCE
    and "let changed = tilePaths[index] != cacheKey" in SOURCE
    and "if changed || path.isEmpty" in SOURCE,
    "same-path avatars must keep their loaded image",
)
require(
    "private var requestedPaths" in SOURCE
    and "requestedPaths[index] == cacheKey" in SOURCE
    and "requestedPaths[index] = cacheKey" in SOURCE,
    "an avatar already loading must not be requested or cleared repeatedly",
)
require(
    "guard let self, self.token == requestToken" in SOURCE,
    "late avatar responses must not overwrite a newer reused cell",
)
require(
    'static func stablePath(_ path: String)' in CORE
    and "ImageCacheKey.avatar(path)" in APP
    and "let cacheKey = ImageCacheKey.stablePath(path)" in SOURCE,
    "signed avatar URLs must share a stable cache key across refreshes",
)
require(
    "private static func cachedImage(path: String, maxSide: CGFloat)" in CORE
    and "_image = State(initialValue: cached)" in CORE
    and "if loadedPath == identity { return }" in CORE,
    "RemoteImage must paint a cached avatar on its first frame without a placeholder flash",
)
require(
    "cacheKey: ImageCacheKey.stablePath(path)" in CORE
    and ".id(ImageCacheKey.stablePath(path))" in CORE
    and "private static func cacheIdentity" in CORE,
    "SwiftUI avatars must keep one cache identity across signed URL refreshes",
)

print("chat-avatar-stability: passed")
