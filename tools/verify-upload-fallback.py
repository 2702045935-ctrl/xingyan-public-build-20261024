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
    "private var uploadBases: [String]" in API
    and "var result = API.directUploadBases" in API
    and "if !result.contains(base)" in API
    and "result.append(base)" in API,
    "media uploads must use the 11/20 direct origin first and keep public ingress as fallback",
)
require(
    API.count("for base in uploadBases {") == 2
    and "req.httpBody = data" in API
    and "fromFile: file" in API,
    "raw image/file uploads must retry through both upload origins",
)
require(
    API.count("var candidates = uploadBases") == 2
    and "private func postDirectUpload" in API
    and "private func uploadRawJPEG" in API,
    "base64 voice/file and JPEG uploads must support both upload origins",
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
