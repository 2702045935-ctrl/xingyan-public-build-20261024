#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PREFIX="${GATEWAY_PREFIX:-/opt/xingyan-gateway/release}"
ETC_DIR="${GATEWAY_ETC_DIR:-/etc/xingyan-gateway}"
NODE="${GATEWAY_NODE_ID:-}"
PORT="${GATEWAY_PORT:-5290}"
START=0

usage() {
  cat <<'USAGE'
用法：
  sudo ./install.sh --node=gateway-a --port=5290 [--start]

可选环境变量：
  GATEWAY_PREFIX       默认 /opt/xingyan-gateway/release
  GATEWAY_ETC_DIR      默认 /etc/xingyan-gateway
  GATEWAY_UPSTREAM_WS  默认 ws://127.0.0.1:5180/__gateway/upstream
  GATEWAY_BACKEND_HTTP 默认 http://127.0.0.1:5180
  GATEWAY_ADMIN_SECRET 必填
USAGE
}

for arg in "$@"; do
  case "$arg" in
    --node=*) NODE="${arg#*=}" ;;
    --port=*) PORT="${arg#*=}" ;;
    --start) START=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $arg" >&2; usage >&2; exit 2 ;;
  esac
done

if [ "$(id -u)" != "0" ]; then
  echo "must run as root" >&2
  exit 1
fi
if [ -z "$NODE" ]; then
  echo "missing --node" >&2
  exit 2
fi
if ! command -v node >/dev/null 2>&1 && [ ! -x /opt/node24/bin/node ]; then
  echo "node 24 is required" >&2
  exit 1
fi

mkdir -p "$PREFIX/server/lib" "$ETC_DIR" /var/lib/xingyan-gateway
install -m 0644 "$ROOT/server/gateway-server.js" "$PREFIX/server/gateway-server.js"
install -m 0644 "$ROOT/server/lib/ws.js" "$PREFIX/server/lib/ws.js"
install -m 0644 "$ROOT/server/lib/connection-governor.js" "$PREFIX/server/lib/connection-governor.js"
install -m 0644 "$ROOT/server/lib/gateway-multiplex.js" "$PREFIX/server/lib/gateway-multiplex.js"
install -m 0644 "$ROOT/server/lib/session-cell.js" "$PREFIX/server/lib/session-cell.js"
install -m 0644 "$ROOT/server/lib/session-ownership.js" "$PREFIX/server/lib/session-ownership.js"
install -m 0644 "$ROOT/server/lib/gateway-session-lease-agent.js" \
  "$PREFIX/server/lib/gateway-session-lease-agent.js"
install -m 0644 "$ROOT/deploy/gateway-cluster/xingyan-gateway@.service" \
  /etc/systemd/system/xingyan-gateway@.service

if ! getent group xingyan-gateway >/dev/null; then
  groupadd --system xingyan-gateway
fi
if ! id xingyan-gateway >/dev/null 2>&1; then
  useradd --system --gid xingyan-gateway --home-dir /var/lib/xingyan-gateway \
    --shell /usr/sbin/nologin xingyan-gateway
fi
chown -R root:xingyan-gateway "$PREFIX"
chown -R xingyan-gateway:xingyan-gateway /var/lib/xingyan-gateway

ENV_FILE="$ETC_DIR/$NODE.env"
if [ ! -f "$ENV_FILE" ]; then
  install -m 0600 "$ROOT/deploy/gateway-cluster/gateway.env.example" "$ENV_FILE"
  sed -i "s/^GATEWAY_PORT=.*/GATEWAY_PORT=$PORT/" "$ENV_FILE"
  sed -i "s/^GATEWAY_NODE_ID=.*/GATEWAY_NODE_ID=$NODE/" "$ENV_FILE"
  echo "created $ENV_FILE; fill GATEWAY_ADMIN_SECRET before starting"
fi

systemctl daemon-reload
echo "installed $NODE"
echo "env: $ENV_FILE"
echo "service: systemctl enable --now xingyan-gateway@$NODE"
if [ "$START" = "1" ]; then
  systemctl enable --now "xingyan-gateway@$NODE"
fi
