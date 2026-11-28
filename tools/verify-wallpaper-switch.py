#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SHEET = (ROOT / "Sources" / "ChatBackgroundSheet.swift").read_text(encoding="utf-8")
CROP = (ROOT / "Sources" / "WallpaperSystem.swift").read_text(encoding="utf-8")
EFFECT = (ROOT / "Sources" / "ChatWallpaperEffect.swift").read_text(encoding="utf-8")
CHAT = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("wallpaper-switch verification failed: " + message)


require(
    "composingImage = image" in SHEET
    and "showingComposer = true" in SHEET
    and "onPreviewPick: beginComposingPreview" in SHEET
    and "originalImage: composingSource" in SHEET
    and "let source = originalImage ?? image" in CROP
    and "previewReady" not in SHEET,
    "photo selection must open the crop page immediately from a lightweight preview",
)
require(
    "private func applyCrop(viewport: CGSize)" in CROP
    and "await Task.detached(priority: .userInitiated)" in CROP
    and "private nonisolated static func render(" in CROP
    and "if applying {\n                        ProgressView()" in CROP
    and ".disabled(applying)" in CROP,
    "crop rendering must run off-main and keep the apply control responsive",
)
require(
    "private let sourceCache = NSCache<NSString, UIImage>()" in EFFECT
    and "private func sourceImage(_ path: String) async -> UIImage?" in EFFECT
    and 'let diskKey = "wallpaper-effect:"' in EFFECT
    and "ImageStore.shared.diskRead(diskKey)" in EFFECT
    and "ImageStore.shared.diskWrite(diskKey, data)" in EFFECT
    and "sourceCache.setObject(image, forKey: key as NSString)" in EFFECT,
    "wallpaper source pixels and rendered effects must use memory and disk caches",
)
require(
    "let localPath = \"local-bg-\" + UUID().uuidString" in SHEET
    and "primeBackgroundCache(path: localPath, image: image)" in SHEET
    and "applyChatBackground(localPath)" in SHEET
    and "ChatBgStore.shared.setGlobal(localPath)" in SHEET,
    "a selected wallpaper must be visible locally before the network upload",
)
require(
    "ChatWallpaperEffectImage(path: backgroundPath" in CHAT
    and ".id(backgroundPath)" in CHAT,
    "chat must render the cached wallpaper path without a gray placeholder flash",
)
require(
    "python3 tools/verify-wallpaper-switch.py" in WORKFLOW,
    "wallpaper responsiveness regression must run in the iOS gate",
)

print("wallpaper-switch: passed")
