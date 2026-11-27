#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
API = (ROOT / "Sources" / "API.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("upload fallback verification failed: " + message)


require(
    "private var uploadBases: [String]" in API
    and "var result = [API.directUploadBases[0]]" in API
    and "if base != result[0] { result.append(base) }" in API,
    "direct upload must keep its fast primary and add the healthy ingress fallback",
)
require(
    API.count("for base in uploadBases {") == 2
    and "req.httpBody = data" in API
    and "fromFile: file" in API,
    "raw image/file uploads must retry through both upload origins",
)
require(
    API.count("for fallback in uploadBases where fallback != base") == 2
    and "private func postDirectUpload" in API
    and "private func uploadRawJPEG" in API,
    "base64 voice/file and JPEG uploads must retry through both upload origins",
)
require(
    "private func uploadFailureMessage(_ data: Data, status: Int)" in API
    and 'dict["error"] as? String' in API
    and 'return "上传失败（HTTP \\(status)）"' in API,
    "upload failures must surface the server reason instead of a generic message",
)
require(
    "python3 tools/verify-upload-fallback.py" in WORKFLOW,
    "upload fallback regression must run in the iOS gate",
)

print("upload-fallback: passed")
