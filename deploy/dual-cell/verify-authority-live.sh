#!/usr/bin/env bash
set -euo pipefail

HOST=$(hostname)
if [ "$HOST" = "ECS-MVEZV" ]; then
  CELL=a
  SHARDS=(0 1 2 3)
  BASE_PORT=17080
elif [ "$HOST" = "ECS-CS6ZN" ]; then
  CELL=b
  SHARDS=(4 5 6)
  BASE_PORT=19080
else
  echo "unexpected host: $HOST" >&2
  exit 2
fi

grep '^SHARD_AUTHORITY' "/etc/xingyan-dual-cell/${CELL}.env" | sort
for shard in "${SHARDS[@]}"; do
  service="xingyan-dual-cell-${CELL}@${shard}.service"
  port=$((BASE_PORT + shard * 100))
  state=$(systemctl is-active "$service" || true)
  health=$(curl -fsS --max-time 3 "http://127.0.0.1:${port}/api/health" || true)
  printf 'shard=%s service=%s health=%s\n' "$shard" "$state" "$health"
done

python3 - "${SHARDS[@]}" <<'PY'
import json
import os
import sqlite3
import sys

root = '/opt/xingyan-dual-cell/physical-r1/stage/shards'
failed = []
for raw in sys.argv[1:]:
    shard = int(raw)
    db_file = os.path.join(root, str(shard), 'shard-authority.sqlite3')
    if not os.path.isfile(db_file):
        failed.append((shard, 'missing-database'))
        continue
    conn = sqlite3.connect('file:' + db_file + '?mode=ro', uri=True)
    try:
        tables = {
            row[0] for row in conn.execute(
                "SELECT name FROM sqlite_master WHERE type='table'"
            )
        }
        for table in (
            'shard_authority', 'chat_sequence', 'chat_state',
            'reliable_messages', 'message_events', 'chat_user_state'
        ):
            if table not in tables:
                failed.append((shard, 'missing-table:' + table))
        identity = conn.execute(
            'SELECT shard_id, topology_id FROM shard_authority WHERE singleton=1'
        ).fetchone()
        if not identity or int(identity[0]) != shard:
            failed.append((shard, 'identity-mismatch'))
        if identity and identity[1] != 'server-b-mainline-shards-7':
            failed.append((shard, 'topology-mismatch'))
        sequence = conn.execute(
            'SELECT COUNT(*), COALESCE(SUM(last_seq), 0) FROM chat_sequence'
        ).fetchone()
        messages = conn.execute(
            'SELECT COUNT(*), COUNT(DISTINCT chat_id) FROM reliable_messages'
        ).fetchone()
        state = conn.execute('SELECT COUNT(*) FROM chat_state').fetchone()
        clears = conn.execute('SELECT COUNT(*) FROM chat_user_state').fetchone()
        bad_sequence = conn.execute(
            '''
            SELECT COUNT(*) FROM (
              SELECT s.chat_id, s.last_seq, COALESCE(MAX(m.seq), 0) AS max_seq
              FROM chat_sequence s
              LEFT JOIN reliable_messages m ON m.chat_id = s.chat_id
              GROUP BY s.chat_id
              HAVING s.last_seq != max_seq
            )
            '''
        ).fetchone()[0]
        bad_state = conn.execute(
            '''
            SELECT COUNT(*) FROM chat_state c
            JOIN chat_sequence s ON s.chat_id = c.chat_id
            WHERE c.seq != s.last_seq
            '''
        ).fetchone()[0]
        if bad_sequence or bad_state:
            failed.append((shard, 'sequence-mismatch'))
        print(
            'db shard=' + str(shard),
            'chats=' + str(sequence[0]),
            'lastSeqSum=' + str(sequence[1]),
            'messageChats=' + str(messages[1]),
            'messages=' + str(messages[0]),
            'states=' + str(state[0]),
            'clearRows=' + str(clears[0]),
            'badSequence=' + str(bad_sequence),
            'badState=' + str(bad_state),
            'size=' + str(os.path.getsize(db_file)),
        )
    finally:
        conn.close()

if failed:
    print('FAILED=' + json.dumps(failed, ensure_ascii=False))
    raise SystemExit(4)
print('authority-live-verify=ok')
PY
