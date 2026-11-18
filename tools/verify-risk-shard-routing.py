#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SERVER = (ROOT / "server" / "server.js").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("risk shard routing verification failed: " + message)


require(
    "function userOwnerDataDir(userId)" in SERVER
    and "resolveRoute(chatRoutePlan, 'user', String(userId))" in SERVER,
    "risk state must resolve the user's owner shard",
)
require(
    "function findViolationAcrossShards(id)" in SERVER
    and "writeJson(hit.file, hit.rows)" in SERVER,
    "violation handling must mutate the shard that owns the record",
)
require(
    "aggregateJsonRows(VIOLATIONS_FILE, 'id')" in SERVER
    and "function loadAllRiskStores()" in SERVER,
    "admin reads must aggregate owner-shard risk state",
)
require(
    "appendFileSync(evp" in SERVER
    and "userOwnerDataDir(user.id)" in SERVER,
    "risk evidence must be written beside the owner's record",
)

print("risk-shard-routing: passed")
