#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SERVER = (ROOT / "server" / "server.js").read_text(encoding="utf-8")
API = (ROOT / "Sources" / "API.swift").read_text(encoding="utf-8")
CHAT = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")
MEDIA = (ROOT / "Sources" / "ChatMediaBubbles.swift").read_text(encoding="utf-8")
MEDIA_ROW = (ROOT / "Sources" / "NativeChatMediaRowCell.swift").read_text(
    encoding="utf-8"
)
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("upload baseline verification failed: " + message)


require(
    'static let directUploadBases = [' in API
    and '"https://43.242.194.89:5443"' in API
    and '"https://43.242.194.89:8443"' in API
    and "private let uploadSession: URLSession" in API
    and "private func uploadRaw(source: RawUploadSource" in API
    and "var roots = API.directUploadBases" in API
    and "roots.append(base)" in API
    and "min(timeout, index == 0 ? 2 : 3)" in API
    and API.count("uploadSession.upload") >= 4,
    "uploads must prefer the 10/20 direct origin with bounded fallback",
)
require(
    "fileSize >= 4 * 1024 * 1024" not in API
    and "TransferUploader.shared.uploadFile(" not in API
    and "TransferUploaderError.unsupported" not in API
    and 'request.httpMethod = "PUT"' in (
        ROOT / "Sources" / "TransferUploader.swift"
    ).read_text(encoding="utf-8")
    and "process.env.ENABLE_TRANSFER_KERNEL !== '0'" in SERVER
    and "(method === 'POST' || method === 'PUT')" in SERVER,
    "chat uploads must keep the faster raw path while the resumable kernel remains diagnostic",
)
require(
    "case .data(let data):" in API
    and "case .file(let file):" in API
    and "fromFile: file,\n                            delegate: delegate" in API
    and "from: data,\n                            delegate: delegate" in API
    and "if API.isConnectivity(error), index + 1 < roots.count" in API,
    "the shared upload transport must stream data and files through direct endpoints",
)
require(
    "private func uploadRawJPEG(" in API
    and 'mime: "image/jpeg"' in API
    and "compressed: true" in API
    and 'req.setValue("1", forHTTPHeaderField: "x-chris-compressed")' in API
    and '"/api/upload"' in API,
    "images must try raw JPEG first and retain the 11/21 base64 fallback",
)
require(
    "private final class ImageUploadProgress" in CHAT
    and "while nextIdx < min(3, list.count)" in CHAT
    and "sendProgress = min(0.82," in CHAT
    and "state.progress * 0.82" in CHAT
    and "sendProgress = 0\n            scrollTick += 1\n            let progress = ImageUploadProgress" in CHAT,
    "multi-image uploads must use the 11/21 three-lane progress flow",
)
require(
    "progress - last >= 0.002" in API
    and "didCompleteWithError error: Error?" in API
    and "onProgress?(1)" in API,
    "upload percentage must follow real URLSession byte callbacks and settle at completion",
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
    and 'Text(Tr("上传中"))' in MEDIA
    and "geo.size.width * value" in MEDIA
    and ".progressViewStyle(.circular)" not in MEDIA
    and "var phase:" not in MEDIA
    and "onRetry:" not in MEDIA
    and ".frame(width: 218)" in MEDIA,
    "media and file placeholders must use the compact 11/21 cards",
)
require(
    "fs.createWriteStream(outPath)" in SERVER
    and "req.pipe(ws2)" in SERVER
    and "req.pipe(uploadCipher).pipe(ws2)" in SERVER
    and "const streamEncrypted = ctype.indexOf('image/') !== 0" in SERVER
    and "const head = Buffer.alloc(4)" in SERVER
    and "async function sealUploadInPlaceStreaming(name)" in SERVER
    and "await sealUploadInPlaceStreaming(name)" in SERVER
    and "await fs.promises.writeFile(outPath, sealUploadBuffer(name, final2))" in SERVER
    and "sealUploadInPlace(name)" in SERVER
    and "receiveEncryptedRaw" not in SERVER,
    "the server upload path must match the 11/21 receive, validate and encrypt flow",
)
require(
    "private let fileTapButton = UIButton(type: .custom)" in MEDIA_ROW
    and "fileTapButton.addTarget(self, action: #selector(tapped), for: .touchUpInside)" in MEDIA_ROW
    and "fileTapButton.isHidden = false" in MEDIA_ROW
    and "fileTapButton.frame = body" in MEDIA_ROW
    and "if let model, case .file = model.kind { return false }" in MEDIA_ROW
    and "private func openFile(_ body: String)" in CHAT
    and "filePreview = FilePreviewData" in CHAT,
    "uploaded file cards must expose a native button that opens the local or downloaded file preview",
)
require(
    "node server/test/transfer-kernel.test.js" in WORKFLOW,
    "the iOS build must retain transfer regression coverage",
)

print("upload-baseline-1121: passed")
