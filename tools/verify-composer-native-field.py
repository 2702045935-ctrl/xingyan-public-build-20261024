#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHAT = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("composer native field verification failed: " + message)


require(
    "private var composerFieldShape: RoundedRectangle" in CHAT
    and "NativeGlassHeaderMaterial(\n"
        "                            forcedDark: composerUsesLightInk" in CHAT
    and "Color.black.opacity(0.28)" in CHAT
    and "Color.white.opacity(0.76)" in CHAT
    and ".clipShape(composerFieldShape)" in CHAT,
    "composer field must use the unified refined native-glass surface",
)
require(
    "composerFieldShape.fill(.regularMaterial)" not in CHAT,
    "composer field must not fall back to an opaque material-only surface",
)
require(
    "ChatComposerTextField(text: $input" in CHAT
    and "struct ChatComposerTextField: UIViewRepresentable" in
    (ROOT / "Sources" / "ChatComposerField.swift").read_text(encoding="utf-8")
    and "final class ComposerTextView: UITextView" in
    (ROOT / "Sources" / "ChatComposerField.swift").read_text(encoding="utf-8")
    and "chatKeyboardManual" not in CHAT
    and "KeyboardLiftDisable" not in CHAT
    and "kbHeight" not in CHAT,
    "composer must use the native UITextView and system-owned keyboard avoidance",
)
require(
    "Color.white.opacity(0.12)" in CHAT
    and "Color.black.opacity(0.045)" in CHAT,
    "composer field needs one restrained native hairline",
)

print("composer-native-field: passed")
