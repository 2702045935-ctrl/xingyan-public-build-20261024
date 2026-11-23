#!/usr/bin/env bash
set -euo pipefail

ID=${1:?shard id required}
APP="$(cd "$(dirname "$0")" && pwd)"
CELL_ID=${DUAL_CELL_ID:?DUAL_CELL_ID is required}
DATA_ROOT=${DUAL_CELL_DATA_ROOT:?DUAL_CELL_DATA_ROOT is required}
DATA_LAYOUT=${DUAL_CELL_DATA_LAYOUT:-shards}
FIRST_PORT=${DUAL_CELL_RUNTIME_BASE_PORT:?DUAL_CELL_RUNTIME_BASE_PORT is required}
ROUTE_PLAN=${DUAL_CELL_ROUTE_PLAN:?DUAL_CELL_ROUTE_PLAN is required}
ROUTE_PLAN_SHA256=${DUAL_CELL_ROUTE_PLAN_SHA256:?DUAL_CELL_ROUTE_PLAN_SHA256 is required}
OWNER_PORTS=${DUAL_CELL_OWNER_PORTS:?DUAL_CELL_OWNER_PORTS is required}
OWNED_SHARDS=${DUAL_CELL_OWNED_SHARDS:-}
FLEET_PLAN=${DUAL_CELL_FLEET_PLAN:-}
NODE_BIN=${DUAL_CELL_NODE_BIN:-node}

COUNT=${DUAL_CELL_SHARD_COUNT:-7}
if [ -n "${DUAL_CELL_SHARD_PORTS:-}" ]; then
  IFS=',' read -r -a SHARD_PORTS <<< "$DUAL_CELL_SHARD_PORTS"
  if [ "${#SHARD_PORTS[@]}" -ne "$COUNT" ]; then
    echo "DUAL_CELL_SHARD_PORTS must contain $COUNT ports" >&2
    exit 1
  fi
  PORT=${SHARD_PORTS[$ID]}
else
  PORT=$((FIRST_PORT + ID * 100))
fi
if [ -n "$FLEET_PLAN" ] && [ -f "$FLEET_PLAN" ]; then
  OWNED_SHARDS=$("$NODE_BIN" -e '
    const fs = require("fs");
    const [file, cellId] = process.argv.slice(1);
    const plan = JSON.parse(fs.readFileSync(file, "utf8"));
    const cell = (plan.cells || []).find((row) => row.id === cellId);
    if (!cell) process.exit(2);
    process.stdout.write((cell.ownerShards || []).join(","));
  ' "$FLEET_PLAN" "$CELL_ID")
fi
export NODE_ENV=production
export HOST=127.0.0.1
export PORT
export HTTPS_PORT=$((PORT + 1000))
export TURN_PORT=$((PORT + 2000))
if [ "$DATA_LAYOUT" = "full" ]; then
  export DATA_DIR="$DATA_ROOT"
else
  export DATA_DIR="${DATA_ROOT}/shards/${ID}"
fi
export CHRIS_LOCAL_ONLY=1
export SHARD_COUNT="$COUNT"
export SHARD_ID="$ID"
export SHARD_BASE_PORT=7080
export SHARD_RUNTIME_BASE_PORT="$FIRST_PORT"
export SHARD_OWNER_PORTS="$OWNER_PORTS"
if [ -n "$OWNED_SHARDS" ] && [[ ",$OWNED_SHARDS," != *",$ID,"* ]]; then
  export SHARD_WRITE_FROZEN=1
fi
export SHARD_RUNTIME_MANIFEST="$APP/shard-runtime-production.json"
export SHARD_TOPOLOGY_FILE="$APP/shard-topologies.json"
export SHARD_ROUTE_PLAN_FILE="$ROUTE_PLAN"
export SHARD_ROUTE_PLAN_FILE_SHA256="$ROUTE_PLAN_SHA256"
export SHARD_ROUTE_PLAN_ENFORCED=1
export BUS_ADDR="${DUAL_CELL_BUS_ADDR:-127.0.0.1:16400}"
export BUS_ID="dual-$CELL_ID-$ID"
export WARM_CHATS=0
export DISABLE_STARTUP_BOT_BACKFILL=1
export AML_RUNTIME_ENABLED=0
export FFMPEG_PATH="${FFMPEG_PATH:-/usr/bin/ffmpeg}"

cd "$APP"
exec "$NODE_BIN" "$APP/server.js"
