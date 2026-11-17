#!/usr/bin/env bash
set -euo pipefail

SHARD=${1:?shard id required}
if [ "$SHARD" -le 3 ]; then
  CELL=a
  NODE=/opt/node24/bin/node
  PORT=$((17080 + SHARD * 100))
  ENV_FILE=/etc/xingyan-dual-cell/a.env
else
  CELL=b
  NODE=/opt/xingyan-prod-replica/runtime/bin/node
  PORT=$((19080 + SHARD * 100))
  ENV_FILE=/etc/xingyan-dual-cell/b.env
fi

STAGE=/opt/xingyan-dual-cell/cutovers/authority-rollout-20261117-1440
DATA=/opt/xingyan-dual-cell/physical-r1/stage/shards/$SHARD
SERVICE="xingyan-dual-cell-${CELL}@${SHARD}.service"
WORK="$STAGE/live-shard-$SHARD-$(date +%s)"
ENV_BACKUP="$WORK/env.before"
DB_TARGET="$DATA/shard-authority.sqlite3"
DB_WORK="$WORK/shard-${SHARD}-authority.sqlite3"

mkdir -p "$WORK"
cp -a "$ENV_FILE" "$ENV_BACKUP"
if [ -f "$DB_TARGET" ]; then
  cp -a "$DB_TARGET" "$WORK/shard-authority.sqlite3.before"
fi
for suffix in -wal -shm; do
  if [ -f "$DB_TARGET$suffix" ]; then
    cp -a "$DB_TARGET$suffix" "$WORK/shard-authority.sqlite3.before$suffix"
  fi
done

restore_and_start() {
  cp -a "$ENV_BACKUP" "$ENV_FILE"
  systemctl start "$SERVICE" || true
}
trap 'restore_and_start' ERR

systemctl stop "$SERVICE"
"$NODE" "$STAGE/tools/import-shard-authority.js" \
  --data "$DATA" \
  --secret "$DATA/secret.key" \
  --database "$DB_WORK" \
  --shard-id "$SHARD" \
  --topology-id server-b-mainline-shards-7 \
  --writer-epoch 1 \
  --out "$WORK/import.json" >/dev/null
"$NODE" "$STAGE/tools/audit-shard-authority.js" \
  --data "$DATA" \
  --secret "$DATA/secret.key" \
  --database "$DB_WORK" \
  --out "$WORK/audit.json" >/dev/null

python3 - "$WORK/import.json" "$WORK/audit.json" <<'PY'
import json
import sys

import_report = json.load(open(sys.argv[1], encoding='utf-8'))
audit_report = json.load(open(sys.argv[2], encoding='utf-8'))
if not import_report.get('ok') or not audit_report.get('ok'):
    raise SystemExit('authority import or audit failed')
if audit_report.get('issues'):
    raise SystemExit('authority audit has issues')
print(
    'audit=ok chats=' + str(audit_report.get('chats'))
    + ' messages=' + str(audit_report.get('messages'))
    + ' issues=' + str(len(audit_report.get('issues') or []))
)
PY

# A previous database may have uncheckpointed sidecars. Never carry those
# into a newly imported authority database.
rm -f "$DB_TARGET.tmp" "$DB_TARGET.tmp-wal" "$DB_TARGET.tmp-shm"
install -m 0600 "$DB_WORK" "$DB_TARGET.tmp"
rm -f "$DB_TARGET-wal" "$DB_TARGET-shm"
mv -f "$DB_TARGET.tmp" "$DB_TARGET"

python3 - "$ENV_FILE" "$SHARD" <<'PY'
import sys

path, shard = sys.argv[1], str(int(sys.argv[2]))
lines = open(path, encoding='utf-8').read().splitlines()
values = {}
for line in lines:
    if '=' in line and not line.lstrip().startswith('#'):
        key, value = line.split('=', 1)
        values[key] = value
current = {
    item.strip() for item in values.get('SHARD_AUTHORITY_SHARDS', '').split(',')
    if item.strip()
}
current.add(shard)
values.update({
    'SHARD_AUTHORITY_ENABLED': '1',
    'SHARD_AUTHORITY_REQUIRED': '1',
    'SHARD_AUTHORITY_READ': '1',
    'SHARD_AUTHORITY_WRITE': '1',
    'SHARD_AUTHORITY_EPOCH': values.get('SHARD_AUTHORITY_EPOCH', '1'),
    'SHARD_AUTHORITY_SHARDS': ','.join(sorted(current, key=int)),
})
values.pop('SHARD_AUTHORITY_SHARD', None)
values.pop('SHARD_AUTHORITY_DB_FILE', None)
ordered = []
seen = set()
for line in lines:
    if '=' not in line or line.lstrip().startswith('#'):
        ordered.append(line)
        continue
    key = line.split('=', 1)[0]
    if key in values and key not in seen:
        ordered.append(key + '=' + values[key])
        seen.add(key)
for key, value in values.items():
    if key not in seen:
        ordered.append(key + '=' + value)
open(path, 'w', encoding='utf-8').write('\n'.join(ordered) + '\n')
PY

systemctl start "$SERVICE"
for attempt in $(seq 1 60); do
  if curl -fsS --max-time 2 "http://127.0.0.1:${PORT}/api/health" >/dev/null; then
    trap - ERR
    curl -fsS --max-time 3 "http://127.0.0.1:${PORT}/api/health"
    echo
    journalctl -u "$SERVICE" --since '2 minutes ago' --no-pager \
      | grep -E '分片权威|fenced|authority|CHRIS Chat|启动失败' | tail -40 || true
    exit 0
  fi
  sleep 1
done

echo "service health timeout: $SERVICE" >&2
restore_and_start
trap - ERR
exit 3
