#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
API = (ROOT / "Sources" / "API.swift").read_text(encoding="utf-8")
SERVER = (ROOT / "server" / "server.js").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("upload fallback verification failed: " + message)


require(
    "private let uploadSession: URLSession" in API
    and "uploadConfig.timeoutIntervalForRequest = 12" in API
    and "httpShouldUsePipelining" not in API
    and API.count("uploadSession.") >= 5,
    "media bytes must use the dedicated 11/26 upload session",
)
require(
    API.count("guard let base = API.directUploadBases.first") >= 4
    and "req.httpBody = data" in API
    and "fromFile: file" in API
    and "for base in uploadBases {" not in API,
    "raw image/file uploads must use one direct origin without retry delay",
)
require(
    "var candidates = uploadBases" not in API
    and "private func postDirectUpload" in API
    and "private func uploadRawJPEG" in API,
    "base64 voice/file and JPEG uploads must stay on the direct origin",
)
require(
    "private func uploadFailureMessage(_ data: Data, status: Int)" in API
    and 'dict["error"] as? String' in API
    and 'return "上传失败（HTTP \\(status)）"' in API,
    "upload failures must surface the server reason instead of a generic message",
)
require(
    'req.setValue(uploadGroup, forHTTPHeaderField: "x-chris-upload-group")' in API
    and "x-chris-upload-group" in SERVER
    and "if (!r.groups.has(uploadGroup))" in SERVER
    and "r.groups.add(uploadGroup)" in SERVER,
    "one multi-image send must consume one upload quota unit",
)
require(
    'let payload: Any = object["data"] ?? object' in API
    and 'JSONSerialization.jsonObject(with: responseData)' in API
    and '(object["ok"] as? Bool) == false' in API,
    "direct uploads must unwrap the server envelope and preserve its error",
)
require(
    "python3 tools/verify-upload-fallback.py" in WORKFLOW,
    "upload fallback regression must run in the iOS gate",
)

print("upload-fallback: passed")
