from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
FILES = [
    *sorted((ROOT / "Sources").glob("*.swift")),
    ROOT / "mac-build.sh",
    ROOT / ".github/workflows/build-ios.yml",
    ROOT / "tools/verify-ipa.py",
]
BLOCKED = [
    "TXLiteAVSDK_TRTC",
    "TXFFmpeg",
    "TXSoundTouch",
    "TRTCBridge",
    "TRTCVideo",
]


def main() -> None:
    hits = []
    for path in FILES:
        text = path.read_text(encoding="utf-8", errors="replace")
        for marker in BLOCKED:
            if marker in text:
                hits.append(f"{path.relative_to(ROOT)}: {marker}")
    if hits:
        raise SystemExit("Tencent media dependency found:\n" + "\n".join(hits))
    print("No Tencent media dependency in client build.")


if __name__ == "__main__":
    main()
