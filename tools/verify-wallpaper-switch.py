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
    and "let stablePath = ImageCacheKey.stablePath(path)" in EFFECT
    and "ImageStore.shared.getBestAvailable(stablePath)" in EFFECT
    and "ImageStore.shared.diskRead(stablePath)" in EFFECT
    and "func getWallpaper(_ path: String) -> UIImage?" in (
        ROOT / "Sources" / "Core.swift"
    ).read_text(encoding="utf-8")
    and "func getBestAvailable(_ path: String) -> UIImage?" in (
        ROOT / "Sources" / "Core.swift"
    ).read_text(encoding="utf-8")
    and "ImageStore.shared.getWallpaper(path)" in EFFECT
    and "ChatWallpaperEffectImage(path: path, effect: effect)" in SHEET,
    "wallpaper previews must reuse the chat page cache before high-resolution rendering",
)
require(
    "@State private var previewReady = false" in SHEET
    and "if previewReady {\n                    backgroundPreview" in SHEET
    and "DispatchQueue.main.asyncAfter(deadline: .now() + 0.06)" in SHEET,
    "the settings sheet must mount immediately and defer only the expensive preview artwork",
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
    and "placeholderImage: wallpaperPreviewImage" in CHAT
    and "private var wallpaperPreviewImage: UIImage?" in CHAT
    and "chatBg.globalPreviewImage()" in CHAT,
    "the immediate preview must feed the blurred wallpaper renderer instead of bypassing its material",
)
require(
    "python3 tools/verify-wallpaper-switch.py" in WORKFLOW,
    "wallpaper responsiveness regression must run in the iOS gate",
)

print("wallpaper-switch: passed")
