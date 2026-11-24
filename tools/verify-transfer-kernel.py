#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SERVER = (ROOT / "server" / "server.js").read_text(encoding="utf-8")
KERNEL = (ROOT / "server" / "transfer-kernel.js").read_text(encoding="utf-8")
CLIENT = (ROOT / "Sources" / "TransferUploader.swift").read_text(encoding="utf-8")
API = (ROOT / "Sources" / "API.swift").read_text(encoding="utf-8")
CHAT = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")
MEDIA = (ROOT / "Sources" / "ChatMediaBubbles.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(encoding="utf-8")
RAW_UPLOAD = SERVER.split(
    "if (parts[0] === 'upload' && parts[1] === 'raw'", 1
)[1].split("if (parts[0] === 'upload' && method", 1)[0]


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("transfer kernel verification failed: " + message)


require(
    "TransferUploader" not in API
    and "/api/transfer" not in API[API.index("func uploadBinary("):
                                     API.index("func send(chatId: String")]
    and 'base + "/api/upload/raw"' in API
    and API.count('base + "/api/upload/raw"') >= 3,
    "the app upload boundary must use only the 11/21 raw upload endpoints",
)
require(
    "let (d, resp) = try await uploadSession.upload(for: req, from: data)"
    in API
    and "uploadSession.upload(\n            for: req,\n            fromFile: file,\n            delegate: delegate"
    in API
    and "req.timeoutInterval = 600" in API,
    "binary and file uploads must use the dedicated high-throughput URLSession",
)
require(
    "private func uploadRawJPEG(" in API
    and 'req.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")'
    in API
    and 'req.setValue("1", forHTTPHeaderField: "x-chris-compressed")' in API
    and '"/api/upload"' in API,
    "images must try raw JPEG first and retain the baseline base64 fallback",
)
require(
    "private final class ImageUploadProgress" in CHAT
    and "sendProgress = 0.02" in CHAT
    and "sendProgress = min(0.82, 0.02 + state.progress * 0.80)" in CHAT,
    "image sends must restore the 11/21 upload percentage mapping",
)
require(
    "let progress: Double?" in MEDIA
    and "ProgressView()" in MEDIA
    and 'return Tr("准备上传…")' in MEDIA
    and 'return Tr("连接中…")' in MEDIA
    and "sendProgress = 0.02" in CHAT
    and "sendingFileProgress = 0.01" in CHAT,
    "the restored 11/21 flow must start image and file progress at its original values",
)
require(
    "enum UploadVisualPhase" in MEDIA
    and "case .preparing" in MEDIA
    and "case .connecting" in MEDIA
    and "case .processing" in MEDIA
    and "var detailText: String = \"\"" in MEDIA
    and "private final class UploadRateMeter" in CHAT
    and "fileUploadDetail = parts.joined(separator: \" · \")" in CHAT,
    "upload cards must expose phases, byte totals, smoothed speed and ETA",
)
require(
    "sendProgress = 0.02" in CHAT
    and "sendProgress = min(0.82, 0.02 + p * 0.80)" in CHAT
    and "sendProgress = 0.9" in CHAT
    and "let value = min(1, max(0.01, p))" in CHAT
    and "uploadFrom = 0.45" in CHAT
    and "uploadFrom = 0.25" in CHAT,
    "image, video, live photo and file percentages must use the 11/21 scale",
)
require(
    "let progress = ImageUploadProgress(count: list.count)" in CHAT
    and "let state = progress.update(index: i, value: p)" in CHAT
    and "while nextIdx < min(6, list.count)" in CHAT,
    "multi-image sends must use six lanes to fill the upload connection pool",
)
require(
    "private let uploadSession: URLSession" in API
    and "let uploadConfig = URLSessionConfiguration.default" in API
    and "uploadConfig.httpMaximumConnectionsPerHost = 8" in API
    and "uploadConfig.networkServiceType = .responsiveData" in API
    and "req.networkServiceType = .responsiveData" in API
    and "URLSessionConfiguration.default" in CLIENT
    and "httpMaximumConnectionsPerHost = 6" in CLIENT
    and "requestCachePolicy = .reloadIgnoringLocalCacheData" in CLIENT
    and "A background session can" in CLIENT
    and "urlSessionDidFinishEvents(forBackgroundURLSession" in CLIENT
    and "handleEventsForBackgroundURLSession" in (
        ROOT / "Sources" / "PushCenter.swift"
    ).read_text(encoding="utf-8"),
    "active uploads must start immediately on a high-throughput foreground URLSession",
)
require(
    "process.env.ENABLE_TRANSFER_KERNEL === '1'" in SERVER
    and "parts[0] === 'transfer'" in SERVER
    and "'/api/transfer/init'" not in SERVER
    and "kernel.putChunk" in SERVER
    and "kernel.complete" in SERVER
    and "inspectTransferFile" in SERVER,
    "server must route the transfer kernel before the legacy raw upload",
)
require(
    "function receiveEncryptedRaw(req, name, tempPath, maxBytes)" in SERVER
    and "pipeline(req, meter, cipher, out" in SERVER
    and "fs.renameSync(tempPath, outPath)" in RAW_UPLOAD
    and "receiveEncryptedRaw(req, name, tempPath, MAX)" in RAW_UPLOAD
    and "fs.writeFileSync(tmpIn, readUploadPlain(outPath))" in RAW_UPLOAD
    and "sealUploadInPlace" not in SERVER,
    "raw uploads must encrypt while receiving instead of rereading and rewriting the whole file",
)
require(
    "function compressedJpegLooksReady(file, name, size)" in SERVER
    and "clientSaidCompressed && compressedJpegLooksReady(outPath, name, size)" in RAW_UPLOAD
    and "head.toString('latin1', 4, 8) === 'ftyp'" in SERVER
    and "execFileSync" not in SERVER[SERVER.index("function videoCanSkipServerShrink"):
                                      SERVER.index("/** 头像字段")],
    "client-normalised images and short videos must avoid full server rewrites and sync ffprobe",
)
require(
    "crypto.createCipheriv(" in KERNEL
    and "'aes-256-ctr'" in KERNEL
    and "counterAt(ivRaw" in KERNEL
    and "fs.createWriteStream(path.join(uploadDir, job.fileName)" in KERNEL
    and "flags: 'r+'" in KERNEL
    and "verifyPlainHash" in KERNEL
    and "job.chunks[String(index)]" in KERNEL,
    "server chunks must be written directly into the encrypted final file",
)
require(
    "job.status = 'processing';" in KERNEL
    and "private func pollComplete(id: String" in CLIENT
    and "timeout: 600" in CLIENT
    and 'state.status == "ready", !state.url.isEmpty' in CLIENT
    and '["failed", "corrupt", "cancelled"].contains(state.status)' in CLIENT
    and "服务器处理超时，进度已保留" in CLIENT,
    "completion must expose processing state and recover from a lost complete response",
)
require(
    "private func startFileProcessingHeartbeat()" in CHAT
    and "private func stopFileProcessingHeartbeat()" in CHAT
    and 'fileUploadDetail = Tr("服务器处理中…") + " · \\(elapsed)s"' in CHAT,
    "file uploads must show live server-processing elapsed time",
)
require(
    "fileUploadFailed = true" in CHAT
    and "fileUploadPhase = .failed" in CHAT
    and "onRetry: retryFailedFileUpload" in CHAT
    and "stageFileRetryCopy" in CHAT
    and "Label(Tr(\"继续上传\")" in MEDIA
    and "fileUploadFailureText" in CHAT,
    "failed file uploads must retain a resumable job and expose a real retry action",
)
require(
    "queueTransferTranscode" in SERVER
    and "setImmediate(async () =>" in SERVER
    and "kind: 'video-transcode'" in SERVER
    and "async function update(ownerId, id, patch)" in KERNEL,
    "video processing must run asynchronously after media is sendable",
)
require(
    "let uploadDirUsageCache = { at: 0, bytes: 0 }" in SERVER
    and "now - uploadDirUsageCache.at < 5000" in SERVER
    and "uploadDirUsageCache = { at: now, bytes: total }" in SERVER,
    "upload capacity checks must reuse a short-lived directory-size cache",
)
require(
    "TransferUploader" not in API
    and "uploadBaselineRaw" not in API
    and "transferBase" not in API
    and "private func uploadRawJPEG(_ data:" in API
    and "func uploadBinaryFile(_ file: URL" in API,
    "media uploads must use only the proven 11/21 raw chain",
)
require(
    "node server/test/transfer-kernel.test.js" in WORKFLOW,
    "the iOS build must execute the resumable transfer integration test",
)

print("transfer-kernel: passed")
