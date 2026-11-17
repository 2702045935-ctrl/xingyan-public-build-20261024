#!/usr/bin/env bash
set -euo pipefail

PEER=root@43.242.194.89
STAGE=/opt/xingyan-dual-cell/physical-r1/stage/shards
KEY=/root/.ssh/xingyan-cluster
ssh_opts=(-i "$KEY" -o BatchMode=yes -o StrictHostKeyChecking=accept-new)
for shard in 0 1 2 3; do
  rsync -a --delete-delay --exclude='*.tmp' --exclude='*.part' \
    -e "ssh ${ssh_opts[*]}" \
    "$PEER:$STAGE/$shard/" "$STAGE/$shard/"
done
for shard in 4 5 6; do
  rsync -a --delete-delay --exclude='*.tmp' --exclude='*.part' \
    -e "ssh ${ssh_opts[*]}" \
    "$STAGE/$shard/" "$PEER:$STAGE/$shard/"
done
touch /run/xingyan-dual-cell-file-sync.ok
