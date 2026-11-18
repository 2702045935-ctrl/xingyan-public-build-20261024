#!/usr/bin/env python3
from __future__ import annotations

import json
import plistlib
import re
import sys
import urllib.parse
from pathlib import Path

import requests


MEDIA_KINDS = {"image", "images", "video", "livephoto", "file"}
UPLOAD_REF = re.compile(r"/uploads/[A-Za-z0-9._-]+")


def media_refs(message: dict) -> list[str]:
    refs = UPLOAD_REF.findall(str(message.get("content") or ""))
    refs.extend(UPLOAD_REF.findall(str(message.get("quote") or "")))
    return list(dict.fromkeys(refs))


def main() -> None:
    prefs_path = Path(sys.argv[1] if len(sys.argv) > 1 else
                      r"C:\Users\Administrator\Documents\Codex\2026-10-22\kan\outputs\iphone-current-prefs.plist")
    with prefs_path.open("rb") as file:
        prefs = plistlib.load(file)
    token = str(prefs.get("chris.token") or "")
    host = str(prefs.get("chris.server") or "").strip()
    if not token or not host:
        raise SystemExit("missing login token or server")
    base = host if host.startswith(("http://", "https://")) else "https://" + host
    base = base.rstrip("/")
    session = requests.Session()
    session.verify = False
    headers = {"Authorization": "Bearer " + token}

    chats_response = session.get(base + "/api/chats", headers=headers, timeout=30)
    chats_response.raise_for_status()
    chats = ((chats_response.json().get("data") or {}).get("chats") or [])
    seen: set[str] = set()
    failures = 0
    checked = 0
    for chat in chats:
        chat_id = str(chat.get("id") or "")
        if not chat_id:
            continue
        response = session.get(
            base + "/api/chats/" + urllib.parse.quote(chat_id) + "/messages?limit=50",
            headers=headers,
            timeout=30,
        )
        if not response.ok:
            print("messages", chat_id, response.status_code)
            continue
        rows = ((response.json().get("data") or {}).get("messages") or [])
        for message in rows:
            if str(message.get("kind") or "") not in MEDIA_KINDS:
                continue
            for ref in media_refs(message):
                if ref in seen:
                    continue
                seen.add(ref)
                checked += 1
                media = session.get(base + ref, headers=headers, timeout=30)
                body = media.content[:120]
                kind = "image" if body.startswith((b"\xff\xd8", b"\x89PNG", b"GIF8", b"RIFF")) else media.headers.get("Content-Type", "")
                state = "ok" if media.ok and body else "missing"
                if state == "missing":
                    failures += 1
                print(state, media.status_code, Path(ref).name, kind)
    print(json.dumps({"checked": checked, "failures": failures, "base": base}, ensure_ascii=False))
    raise SystemExit(1 if failures else 0)


if __name__ == "__main__":
    main()
