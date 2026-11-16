#!/usr/bin/env bash
set -euo pipefail

ID=${1:?shard id required}
COUNT=7
FIRST_PORT=7080
PORT=$((FIRST_PORT + ID * 100))
APP="$(cd "$(dirname "$0")" && pwd)"
DATA=/opt/xingyan-mainline/data
ROUTE_PLAN=/opt/xingyan-mainline/releases/20261116-shard-baseline/route-plan.json
NODE=/opt/xingyan-prod-replica/runtime/bin/node

export NODE_ENV=production
export HOST=127.0.0.1
export PORT
export HTTPS_PORT=$((PORT + 1000))
export TURN_PORT=$((PORT + 2000))
export DATA_DIR="$DATA"
export CHRIS_LOCAL_ONLY=1
export SHARD_COUNT="$COUNT"
export SHARD_ID="$ID"
export SHARD_BASE_PORT="$FIRST_PORT"
export SHARD_RUNTIME_MANIFEST="$APP/shard-runtime-production.json"
export SHARD_TOPOLOGY_FILE="$APP/shard-topologies.json"
export SHARD_ROUTE_PLAN_FILE="$ROUTE_PLAN"
export SHARD_ROUTE_PLAN_FILE_SHA256=c02d3ccb14304371044aad4096cc9501d072566c232fb51700d8e228e68d519c
export SHARD_ROUTE_PLAN_ENFORCED=0
export BUS_ADDR=127.0.0.1:16400
export BUS_ID="shard-$ID-candidate"
export WARM_CHATS=3000
export FFMPEG_PATH=/usr/bin/ffmpeg

cd "$APP"
exec "$NODE" "$APP/server.js"
