#!/usr/bin/env bash
set -euo pipefail

PEER=root@43.242.194.89
STAGE=/opt/xingyan-dual-cell/physical-r1/stage/shards
KEY=/root/.ssh/xingyan-cluster
ssh_opts=(-i "$KEY" -o BatchMode=yes -o StrictHostKeyChecking=accept-new)
CHECKSUM_MARKER=/run/xingyan-dual-cell-file-sync.checksum

# rsync's default only compares size and mtime. Provisioning can give two
# different files the same timestamp, which previously left replica secrets
# and live JSON files stale while rsync reported success. Verify full content
# once at startup and at most once an hour; the other passes stay incremental.
checksum_args=()
if [ ! -f "$CHECKSUM_MARKER" ] || [ -n "$(find "$CHECKSUM_MARKER" -mmin +60 -print -quit)" ]; then
  checksum_args=(--checksum)
fi

for shard in 0 1 2 3; do
  rsync -a "${checksum_args[@]}" --delete-delay \
    --exclude='*.tmp' --exclude='*.part' \
    -e "ssh ${ssh_opts[*]}" \
    "$PEER:$STAGE/$shard/" "$STAGE/$shard/"
done
for shard in 4 5 6; do
  rsync -a "${checksum_args[@]}" --delete-delay \
    --exclude='*.tmp' --exclude='*.part' \
    -e "ssh ${ssh_opts[*]}" \
    "$STAGE/$shard/" "$PEER:$STAGE/$shard/"
done
touch "$CHECKSUM_MARKER"
touch /run/xingyan-dual-cell-file-sync.ok
