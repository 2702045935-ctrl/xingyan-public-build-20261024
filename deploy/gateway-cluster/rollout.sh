#!/usr/bin/env bash
set -euo pipefail

BACKEND="${GATEWAY_BACKEND_HTTP:?set GATEWAY_BACKEND_HTTP}"
SECRET="${GATEWAY_ADMIN_SECRET:?set GATEWAY_ADMIN_SECRET}"
FROM="${GATEWAY_CANARY_FROM:-1}"
TO="${GATEWAY_CANARY_TO:-5}"
APPLY=0

for arg in "$@"; do
  case "$arg" in
    --apply) APPLY=1 ;;
    --from=*) FROM="${arg#*=}" ;;
    --to=*) TO="${arg#*=}" ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

preflight() {
  node "$(dirname "${BASH_SOURCE[0]}")/../../server/tools/gateway-cluster-preflight.js" \
    --backend="$BACKEND" \
    --secret="$SECRET" \
    --directory-backend="${GATEWAY_DIRECTORY_BACKEND:-etcd}" \
    --fanout-mode=canary \
    --canary-percent="$1" \
    --gateways="${GATEWAY_ENDPOINTS:-}"
}

preflight "$FROM"
if [ "$APPLY" = "1" ]; then
  curl --fail --silent --show-error \
    -H "X-Gateway-Admin-Secret: $SECRET" \
    -H "Content-Type: application/json" \
    -X POST "$BACKEND/__gateway/canary" \
    --data "{\"percent\":$TO,\"reason\":\"rollout $FROM -> $TO\"}"
  preflight "$TO"
  echo "canary moved $FROM -> $TO"
else
  echo "preflight passed; dry-run only. add --apply to change canary"
fi
