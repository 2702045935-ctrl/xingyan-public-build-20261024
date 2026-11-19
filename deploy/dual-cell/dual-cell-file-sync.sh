#!/usr/bin/env bash
set -uo pipefail

PEER=root@43.242.194.89
STAGE=/opt/xingyan-dual-cell/physical-r1/stage/shards
KEY=/root/.ssh/xingyan-cluster
RUN_DIR=/run/xingyan-dual-cell-file-sync
CHECKSUM_MARKER="$RUN_DIR/checksum"
OK_MARKER="$RUN_DIR/ok"
STATUS_FILE="$RUN_DIR/status.json"
ssh_opts=(-i "$KEY" -o BatchMode=yes -o StrictHostKeyChecking=accept-new)

mkdir -p "$RUN_DIR"
rm -f "$OK_MARKER"
started_at="$(date -Is)"
printf '{"updatedAt":"%s","ok":false,"state":"running","failedShards":[]}\n' "$started_at" > "$STATUS_FILE.tmp"
mv "$STATUS_FILE.tmp" "$STATUS_FILE"

# rsync's default only compares size and mtime. Provisioning can give two
# different files the same timestamp, so run a deeper check at startup and at
# most once per hour. metrics-history is high-frequency telemetry; synchronizing
# it directly races with its writer and used to abort the whole replication loop.
checksum_args=()
if [ ! -f "$CHECKSUM_MARKER" ] || [ -n "$(find "$CHECKSUM_MARKER" -mmin +60 -print -quit)" ]; then
  checksum_args=(--checksum)
fi

failed_shards=()

sync_shard() {
  local shard="$1"
  local source="$2"
  local destination="$3"
  local marker="$RUN_DIR/shard-$shard.ok"
  rm -f "$marker"
  if rsync -a "${checksum_args[@]}" --delete-delay \
    --exclude='*.tmp' --exclude='*.part' \
    --exclude='metrics-history.jsonl' \
    -e "ssh ${ssh_opts[*]}" \
    "$source" "$destination"; then
    date -Is > "$marker"
    return 0
  fi
  failed_shards+=("$shard")
  return 1
}

for shard in 0 1 2 3; do
  sync_shard "$shard" "$PEER:$STAGE/$shard/" "$STAGE/$shard/" || true
done
for shard in 4 5 6; do
  sync_shard "$shard" "$STAGE/$shard/" "$PEER:$STAGE/$shard/" || true
done

now="$(date -Is)"
if [ "${#failed_shards[@]}" -eq 0 ]; then
  touch "$CHECKSUM_MARKER"
  printf '{"updatedAt":"%s","ok":true,"state":"ok","failedShards":[]}\n' "$now" > "$STATUS_FILE.tmp"
  mv "$STATUS_FILE.tmp" "$STATUS_FILE"
  touch "$OK_MARKER"
  exit 0
fi

failed_csv="$(IFS=,; echo "${failed_shards[*]}")"
printf '{"updatedAt":"%s","ok":false,"state":"failed","failedShards":[%s]}\n' "$now" "$failed_csv" > "$STATUS_FILE.tmp"
mv "$STATUS_FILE.tmp" "$STATUS_FILE"
echo "dual-cell replication failed shards: $failed_csv" >&2
exit 1
