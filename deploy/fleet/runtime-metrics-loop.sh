#!/usr/bin/env bash
set -uo pipefail

ROOT=/opt/xingyan-dual-cell/release-r1
NODE=/opt/node24/bin/node
STATE=/var/lib/xingyan-dual-cell
mkdir -p "$STATE"

while true; do
  "$NODE" "$ROOT/tools/collect-runtime-fleet-metrics.js" \
    --cell=cell-a-43 \
    --ports=17080,17180,17280,17380,17480,17580,17680 \
    --data-root=/opt/xingyan-dual-cell \
    --out="$STATE/cell-a-43.json" || true

  ssh -i /root/.ssh/xingyan-cluster -o BatchMode=yes \
    -o StrictHostKeyChecking=accept-new root@192.140.179.176 \
    "/opt/xingyan-prod-replica/runtime/bin/node $ROOT/tools/collect-runtime-fleet-metrics.js \
      --cell=cell-b-192 \
      --ports=19080,19180,19280,19380,19480,19580,19680 \
      --data-root=/opt/xingyan-dual-cell" \
    > "$STATE/cell-b-192.json.tmp" 2>/dev/null \
    && mv -f "$STATE/cell-b-192.json.tmp" "$STATE/cell-b-192.json" || true

  if [ -f "$STATE/cell-a-43.json" ] && [ -f "$STATE/cell-b-192.json" ]; then
    "$NODE" "$ROOT/tools/fleet-metrics-merge.js" \
      --cell="cell-a-43:$STATE/cell-a-43.json" \
      --cell="cell-b-192:$STATE/cell-b-192.json" \
      --out="$STATE/fleet-metrics.json" || true
  fi
  sleep 30
done
