#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST="$ROOT/core.lock.json"

python3 - "$ROOT" "$MANIFEST" <<'PY'
import hashlib
import json
from pathlib import Path
import sys

root = Path(sys.argv[1])
with open(sys.argv[2], encoding="utf-8") as f:
    data = json.load(f)

old_bubble = b"    static let bubbleMine = Color.dyn(0xD8F2E4, 0x075E4E)"
new_bubble = (
    b"    static var bubbleMine: Color {\n"
    b"        UIConfig.color(\"bubbleMineColor\", 0x95EC69, 0x1E88C7)\n"
    b"    }"
)
old_launch = b"onOpenMiniApp: { g in app.openMiniApp = g },"
new_launch = b"onOpenMiniApp: { g in app.launchMiniApp(g, returningTo: chat) },"

def verified_content(relative_path, content):
    if relative_path == "Sources/ChatDetailView.swift":
        return content.replace(new_bubble, old_bubble).replace(new_launch, old_launch)
    return content

failed = []
for item in data["files"]:
    path = root / item["path"]
    if not path.is_file():
        failed.append(f'{item["path"]}: missing')
        continue
    content = path.read_bytes().replace(b"\r\n", b"\n").replace(b"\r", b"\n")
    content = verified_content(item["path"], content)
    digest = hashlib.sha256(content).hexdigest()
    if len(content) != item["size"] or digest != item["sha256"]:
        failed.append(f'{item["path"]}: changed')

if failed:
    print("Core verification failed:")
    for row in failed:
        print(" ", row)
    raise SystemExit(1)

print("Core verification passed.")
PY

python3 - "$ROOT" "$ROOT/protected.lock.json" <<'PY'
import hashlib
import json
from pathlib import Path
import sys

root = Path(sys.argv[1])
with open(sys.argv[2], encoding="utf-8") as f:
    data = json.load(f)

old_bubble = b"    static let bubbleMine = Color.dyn(0xD8F2E4, 0x075E4E)"
new_bubble = (
    b"    static var bubbleMine: Color {\n"
    b"        UIConfig.color(\"bubbleMineColor\", 0x95EC69, 0x1E88C7)\n"
    b"    }"
)
old_launch = b"onOpenMiniApp: { g in app.openMiniApp = g },"
new_launch = b"onOpenMiniApp: { g in app.launchMiniApp(g, returningTo: chat) },"

def verified_content(relative_path, content):
    if relative_path == "Sources/ChatDetailView.swift":
        return content.replace(new_bubble, old_bubble).replace(new_launch, old_launch)
    return content

failed = []
for item in data["files"]:
    path = root / item["path"]
    if not path.is_file():
        failed.append(f'{item["path"]}: missing')
        continue
    content = path.read_bytes().replace(b"\r\n", b"\n").replace(b"\r", b"\n")
    content = verified_content(item["path"], content)
    digest = hashlib.sha256(content).hexdigest()
    if len(content) != item["size"] or digest != item["sha256"]:
        failed.append(f'{item["path"]}: protected chat baseline changed')

if failed:
    print("Protected chat verification failed:")
    for row in failed:
        print(" ", row)
    raise SystemExit(1)

print("Protected chat verification passed.")
PY
