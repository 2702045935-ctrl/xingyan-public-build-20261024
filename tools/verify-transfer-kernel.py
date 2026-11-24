#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SERVER = (ROOT / "server" / "server.js").read_text(encoding="utf-8")
API = (ROOT / "Sources" / "API.swift").read_text(encoding="utf-8")
CHAT = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")
MEDIA = (ROOT / "Sources" / "ChatMediaBubbles.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("upload baseline verification failed: " + message)


require(
    "TransferUploader" not in API
    and "uploadSession" not in API
    and 'base + "/api/upload/raw"' in API
    and API.count('base + "/api/upload/raw"') >= 3,
    "media uploads must use only the proven 11/21 raw endpoint",
)
require(
    "req.httpBody = data\n        let (d, resp) = try await session.data(for: req)"
    in API
    and "session.upload(\n            for: req,\n            fromFile: file,\n            delegate: delegate"
    in API
    and "(d, resp) = try await session.upload(\n                for: req,\n                from: data,\n                delegate: delegate"
    in API,
    "binary and file uploads must use the original 11/21 URLSession modes",
)
require(
    "private func uploadRawJPEG(" in API
    and 'req.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")' in API
    and 'req.setValue("1", forHTTPHeaderField: "x-chris-compressed")' in API
    and '"/api/upload"' in API,
    "images must try raw JPEG first and retain the 11/21 base64 fallback",
)
require(
    "private final class ImageUploadProgress" in CHAT
    and "while nextIdx < min(3, list.count)" in CHAT
    and "sendProgress = min(0.82, 0.02 + state.progress * 0.80)" in CHAT,
    "multi-image uploads must use the 11/21 three-lane progress flow",
)
require(
    "@State private var sendingPreview: UIImage?" in CHAT
    and "@State private var sendProgress: Double = 0" in CHAT
    and "@State private var sendingFileProgress: Double? = nil" in CHAT
    and "sendingPreviews" not in CHAT
    and "mediaUploadPhase" not in CHAT
    and "fileUploadPhase" not in CHAT
    and "UploadRateMeter" not in CHAT,
    "the upload-in-progress page must match the 11/21 simple state",
)
require(
    "SendingVideoBubble(cover: sendingPreview, progress: sendProgress)" in CHAT
    and "progress: sendingFileProgress ?? 0" in CHAT
    and "struct SendingVideoBubble: View" in MEDIA
    and "struct SendingFileBubble: View" in MEDIA
    and "var phase:" not in MEDIA
    and "onRetry:" not in MEDIA
    and ".frame(width: 218)" in MEDIA,
    "media and file placeholders must use the compact 11/21 cards",
)
require(
    "fs.createWriteStream(outPath)" in SERVER
    and "req.pipe(ws2)" in SERVER
    and "sealUploadInPlace(name)" in SERVER
    and "receiveEncryptedRaw" not in SERVER,
    "the server upload path must match the 11/21 receive, validate and encrypt flow",
)
require(
    "node server/test/transfer-kernel.test.js" in WORKFLOW,
    "the iOS build must retain transfer regression coverage",
)

print("upload-baseline-1121: passed")
