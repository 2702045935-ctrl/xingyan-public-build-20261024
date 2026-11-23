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


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("transfer kernel verification failed: " + message)


require(
    '"/api/transfer/init"' in CLIENT
    and '"/api/transfer/\\(id)/chunk"' in CLIENT
    and '"/api/transfer/\\(id)/complete"' in CLIENT
    and "x-transfer-chunk-index" in CLIENT
    and "x-transfer-chunk-sha256" in CLIENT,
    "client must use the declared resumable transfer protocol",
)
require(
    "TransferJobStore" in CLIENT
    and "jobs.json" in CLIENT
    and "fetchStatus(id: existing.remoteId" in CLIENT
    and "let pending = remote.missing" in CLIENT
    and "let preferredWorkers = size >= 16 * 1024 * 1024 ? 6 : 3" in CLIENT
    and "let workerCount = min(preferredWorkers, pending.count)" in CLIENT
    and "withThrowingTaskGroup" in CLIENT,
    "client must persist jobs and resume acknowledged chunks with adaptive concurrency",
)
require(
    "allowsLegacyFallback" not in CLIENT
    and "TransferJobStore.shared.remove(key)" in CLIENT
    and "error.allowsLegacyFallback" not in API
    and "uploadBinaryFileLegacy" not in API
    and "uploadBinaryLegacy" not in API,
    "large media uploads must never silently fall back to a single whole-file request",
)
require(
    "TransferCapabilityCache" not in CLIENT
    and "private func initialize(" in CLIENT
    and '"/api/transfer/init"' in CLIENT
    and "parts[1] === 'capabilities'" in SERVER,
    "uploads must enter the transfer kernel directly without an extra capability round trip",
)
require(
    "SHA256" in CLIENT
    and "fileFingerprint" in CLIENT
    and "readChunk" in CLIENT
    and "data.subdata(in: start..<end)" in CLIENT,
    "client hashing and chunk reads must stay bounded",
)
require(
    "let progress: Double?" in MEDIA
    and "ProgressView()" in MEDIA
    and 'return Tr("准备上传…")' in MEDIA
    and 'return Tr("连接中…")' in MEDIA
    and "sendProgress = 0.02" not in CHAT
    and "sendingFileProgress = 0.01" not in CHAT,
    "preparing, hashing and compression must not masquerade as upload percentages",
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
    "sendProgress = min(1, max(0, p))" in CHAT
    and "let value = min(1, max(0, p))" in CHAT,
    "upload percentages must come from actual sent chunk bytes",
)
require(
    "func uploadPreparedJPEGForSend(" in API
    and "private final class ActualUploadProgress" in CHAT
    and "let totalBytes = prepared.reduce(Int64(0))" in CHAT
    and "value: p," in CHAT
    and "bytes: Int64(item.data.count)" in CHAT
    and "ImageUploadProgress" not in CHAT,
    "multi-image progress must aggregate actual prepared and sent bytes",
)
require(
    "URLSessionConfiguration.default" in CLIENT
    and "httpMaximumConnectionsPerHost = 6" in CLIENT
    and "requestCachePolicy = .reloadIgnoringLocalCacheData" in CLIENT
    and "A background session can" in CLIENT
    and "urlSessionDidFinishEvents(forBackgroundURLSession" in CLIENT
    and "handleEventsForBackgroundURLSession" in (
        ROOT / "Sources" / "PushCenter.swift"
    ).read_text(encoding="utf-8"),
    "active chunk uploads must start immediately on a foreground URLSession",
)
require(
    "parts[0] === 'transfer'" in SERVER
    and "'/api/transfer/init'" not in SERVER
    and "kernel.putChunk" in SERVER
    and "kernel.complete" in SERVER
    and "inspectTransferFile" in SERVER,
    "server must route the transfer kernel before the legacy raw upload",
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
    "TransferUploader.shared.uploadData" in API
    and "TransferUploader.shared.uploadFile" in API
    and API.count("/api/upload/raw") == 0,
    "all chunk-capable upload entry points must use the resumable kernel exclusively",
)
require(
    "node server/test/transfer-kernel.test.js" in WORKFLOW,
    "the iOS build must execute the resumable transfer integration test",
)

print("transfer-kernel: passed")
