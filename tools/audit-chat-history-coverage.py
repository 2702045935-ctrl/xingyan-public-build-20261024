#!/usr/bin/env python3
"""Read-only group history coverage audit.

Only counters, IDs and timestamps are reported. Message bodies are never
printed or written.
"""

from __future__ import annotations

import argparse
import json
import plistlib
from pathlib import Path

import requests
import urllib3


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_PREFS = ROOT / "diagnostics" / "chris-prefs.plist"


def base_url(server: str) -> str:
    base = server if server.startswith(("http://", "https://")) else "https://" + server
    if server == "mail.xingyanmail.site:443":
        base += "/xy"
    return base.rstrip("/")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--prefs", default=str(DEFAULT_PREFS))
    parser.add_argument("--limit", type=int, default=100)
    parser.add_argument("--max-pages", type=int, default=400)
    parser.add_argument("--chat-id", default="")
    parser.add_argument("--out", default="")
    args = parser.parse_args()

    urllib3.disable_warnings()
    with Path(args.prefs).open("rb") as file:
        prefs = plistlib.load(file)
    token = str(prefs.get("chris.token") or "")
    server = str(prefs.get("chris.server") or "")
    if not token or not server:
        raise SystemExit("missing login token or server")
    base = base_url(server)
    session = requests.Session()
    session.trust_env = False
    session.verify = False
    session.headers.update({
        "Authorization": "Bearer " + token,
        "User-Agent": "Xingyan-History-Audit/1",
    })

    response = session.get(base + "/api/chats", timeout=30, verify=False)
    response.raise_for_status()
    chats = (response.json().get("data") or {}).get("chats") or []
    groups = [chat for chat in chats if chat.get("type") == "group" and chat.get("id")]
    if args.chat_id:
        groups = [chat for chat in groups if str(chat.get("id")) == args.chat_id]
        if not groups:
            raise SystemExit("requested group was not found")
    reports = []
    for chat in groups:
        chat_id = str(chat["id"])
        before = None
        seqs: set[int] = set()
        dates: list[str] = []
        pages = 0
        has_more = False
        stopped = "max-pages"
        while pages < max(1, args.max_pages):
            params = {"limit": str(max(1, min(100, args.limit))), "all": "1"}
            if before is not None:
                params["before"] = str(before)
            page_response = session.get(
                base + f"/api/chats/{chat_id}/messages",
                params=params,
                timeout=60,
                verify=False,
            )
            page_response.raise_for_status()
            payload = page_response.json().get("data") or {}
            rows = payload.get("messages") or []
            pages += 1
            for row in rows:
                seq = int(row.get("seq") or 0)
                if seq > 0:
                    seqs.add(seq)
                created = str(row.get("createdAt") or "")
                if created:
                    dates.append(created)
            has_more = bool(payload.get("hasMore"))
            numeric = [
                int(row.get("seq") or 0)
                for row in rows
                if int(row.get("seq") or 0) > 0
            ]
            if not has_more:
                stopped = "server-end"
                break
            if not numeric:
                stopped = "has-more-without-seq"
                break
            next_before = min(numeric)
            if before is not None and next_before >= before:
                stopped = "cursor-did-not-advance"
                break
            before = next_before
        reports.append({
            "chatId": chat_id,
            "title": str(chat.get("title") or ""),
            "memberCount": int(chat.get("memberCount") or 0),
            "pages": pages,
            "uniqueMessagesWithSeq": len(seqs),
            "firstSeq": min(seqs) if seqs else None,
            "lastSeq": max(seqs) if seqs else None,
            "earliestCreatedAt": min(dates) if dates else None,
            "latestCreatedAt": max(dates) if dates else None,
            "hasMoreAfterAudit": has_more,
            "stoppedReason": stopped,
        })

    report = {
        "scope": "Read-only production history coverage; no message bodies emitted",
        "base": base,
        "groups": reports,
        "pass": all(row["stoppedReason"] == "server-end" for row in reports),
    }
    text = json.dumps(report, ensure_ascii=False, indent=2) + "\n"
    print(text)
    if args.out:
        output = Path(args.out)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(text, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
