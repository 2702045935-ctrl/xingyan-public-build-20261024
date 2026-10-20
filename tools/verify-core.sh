#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST="$ROOT/core.lock.json"
FAILED=0

while IFS=$'\t' read -r REL SIZE HASH; do
  FILE="$ROOT/$REL"
  if [[ ! -f "$FILE" ]]; then
    echo "$REL: missing"
    FAILED=1
    continue
  fi
  ACTUAL_SIZE="$(wc -c < "$FILE" | tr -d ' ')"
  ACTUAL_HASH="$(shasum -a 256 "$FILE" | awk '{print $1}')"
  if [[ "$ACTUAL_SIZE" != "$SIZE" || "$ACTUAL_HASH" != "$HASH" ]]; then
    echo "$REL: changed"
    FAILED=1
  fi
done < <(python3 - "$MANIFEST" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    data = json.load(f)
for item in data["files"]:
    print(item["path"], item["size"], item["sha256"], sep="\t")
PY
)

if [[ "$FAILED" -ne 0 ]]; then
  exit 1
fi

echo "Core verification passed."
