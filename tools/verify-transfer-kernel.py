#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SERVER = (ROOT / "server" / "server.js").read_text(encoding="utf-8")
KERNEL = (ROOT / "server" / "transfer-kernel.js").read_text(encoding="utf-8")
CLIENT = (ROOT / "Sources" / "TransferUploader.swift").read_text(encoding="utf-8")
API = (ROOT / "Sources" / "API.swift").read_text(encoding="utf-8")
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
    and "let workerCount = min(3, pending.count)" in CLIENT
    and "withThrowingTaskGroup" in CLIENT,
    "client must persist jobs and resume acknowledged chunks with bounded concurrency",
)
require(
    "SHA256" in CLIENT
    and "fileFingerprint" in CLIENT
    and "readChunk" in CLIENT
    and "data.subdata(in: start..<end)" in CLIENT,
    "client hashing and chunk reads must stay bounded",
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
    "TransferUploader.shared.uploadData" in API
    and "TransferUploader.shared.uploadFile" in API
    and API.count("/api/upload/raw") == 2,
    "API upload entry points must use the kernel; raw upload remains legacy-only",
)
require(
    "node server/test/transfer-kernel.test.js" in WORKFLOW,
    "the iOS build must execute the resumable transfer integration test",
)

print("transfer-kernel: passed")
