#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SERVER = (ROOT / "server" / "server.js").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("pin owner routing verification failed: " + message)


require(
    "postShardJson(ownerPort, '/__shard/chat-pin'" in SERVER,
    "public chat pin requests must forward to the chat owner shard",
)
require(
    "parsed.pathname === '/__shard/chat-pin'" in SERVER
    and "chatOwnerPort(chatId) !== PORT" in SERVER,
    "owner shard must validate and persist chat pin state",
)
require(
    "chat.pinnedFor = Array.from(set)" in SERVER
    and "saveChats()" in SERVER,
    "pin state must persist on the owning shard",
)

print("pin-owner-routing: passed")
