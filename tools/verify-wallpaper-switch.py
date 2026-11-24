#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SHEET = (ROOT / "Sources" / "ChatBackgroundSheet.swift").read_text(encoding="utf-8")
CROP = (ROOT / "Sources" / "WallpaperSystem.swift").read_text(encoding="utf-8")
EFFECT = (ROOT / "Sources" / "ChatWallpaperEffect.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)
CHAT = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("wallpaper-switch verification failed: " + message)


start = SHEET.index("private func beginComposing")
end = SHEET.index("private func applyChatBackground", start)
block = SHEET[start:end]
require(
    "composingImage = image" in block
    and "showingComposer = true" in block
    and "downsampledWallpaper" not in block
    and "Task.detached" not in block,
    "photo selection must open crop immediately without a second decode wait",
)
require(
    "@State private var applying = false" in CROP
    and "private func applyCrop(viewport: CGSize)" in CROP
    and "await Task.detached(priority: .userInitiated)" in CROP
    and "private nonisolated static func render(" in CROP
    and "await MainActor.run {\n                applying = false\n                onApply(rendered)"
    in CROP,
    "wallpaper crop rendering must run off the main actor and apply atomically",
)
require(
    "if applying {\n                        ProgressView()" in CROP
    and ".disabled(applying)" in CROP,
    "the crop action must stay responsive and expose a clear applying state",
)
require(
    "private let sourceCache = NSCache<NSString, UIImage>()" in EFFECT
    and "private func diskCacheImage(key: String) async -> UIImage?" in EFFECT
    and "private func saveDiskCache(_ image: UIImage, key: String) async" in EFFECT
    and "ImageStore.shared.get(ImageCacheKey.stablePath(path))" in EFFECT
    and "let placeholder = ImageStore.shared.get(" in EFFECT,
    "rendered wallpapers must reuse source/effect caches across chat entries",
)
require(
    "var placeholder: Color? = nil" in (
        ROOT / "Sources" / "Core.swift"
    ).read_text(encoding="utf-8")
    and "placeholder: ChatTheme.page" in CHAT
    and ".id(backgroundPath)" in CHAT,
    "chat wallpaper loads must use the theme canvas instead of a gray flash",
)
require(
    "private var previewImages: [String: UIImage] = [:]" in SHEET
    and "func setPreview(chatId: String, path: String, image: UIImage?)" in SHEET
    and "func previewImage(chatId: String) -> UIImage?" in SHEET
    and "func globalPreviewImage() -> UIImage?" in SHEET
    and "applyChatBackground(localPath, image: image)" in SHEET
    and "if let preview = chatBg.previewImage(chatId: chat.id)" in CHAT
    and "chatBg.globalPreviewImage()" in CHAT,
    "cropped wallpapers must render from an immediate in-memory preview",
)
require(
    "python3 tools/verify-wallpaper-switch.py" in WORKFLOW,
    "wallpaper responsiveness regression must run in the iOS gate",
)

print("wallpaper-switch: passed")
