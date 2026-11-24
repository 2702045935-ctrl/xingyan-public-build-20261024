#!/usr/bin/env python3
"""Verify the first long-connection control-plane foundation."""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    governor = (ROOT / "server/lib/connection-governor.js").read_text(encoding="utf-8")
    server = (ROOT / "server/server.js").read_text(encoding="utf-8")
    test = (ROOT / "server/test/connection-governor.test.js").read_text(encoding="utf-8")
    required_governor = [
        "maxTotal",
        "maxPerUser",
        "maxPerIp",
        "drain()",
        "resume()",
        "snapshot()",
    ]
    required_server = [
        "ConnectionGovernor",
        "connectionGovernor.admit",
        "connectionGovernor.release",
        "__gateway/metrics",
        "__gateway/drain",
        "__gateway/resume",
        "GATEWAY_ADMIN_SECRET",
        "gateway: connectionGovernor.snapshot()",
    ]
    for needle in required_governor:
        if needle not in governor:
            raise AssertionError(f"connection governor missing {needle}")
    for needle in required_server:
        if needle not in server:
            raise AssertionError(f"server foundation missing {needle}")
    for needle in ["user-limit", "ip-limit", "draining", "released"]:
        if needle not in test:
            raise AssertionError(f"foundation test missing {needle}")
    directory = (ROOT / "server/lib/gateway-directory.js").read_text(encoding="utf-8")
    for needle in ["register(", "heartbeat(", "claim(", "renew(", "release(", "pick("]:
        if needle not in directory:
            raise AssertionError(f"gateway directory missing {needle}")
    gateway = (ROOT / "server/gateway-server.js").read_text(encoding="utf-8")
    for needle in ["GATEWAY_UPSTREAM_WS", "/__gateway/upstream", "send('open'", "governor.admit"]:
        if needle not in gateway:
            raise AssertionError(f"independent gateway missing {needle}")
    print("long connection foundation: passed")


if __name__ == "__main__":
    main()
