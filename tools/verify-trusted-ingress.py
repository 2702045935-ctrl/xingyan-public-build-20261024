#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
API = (ROOT / "Sources" / "API.swift").read_text(encoding="utf-8")
REALTIME = (ROOT / "Sources" / "Realtime.swift").read_text(encoding="utf-8")
INFO = (ROOT / "Info.plist").read_text(encoding="utf-8")


def check(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("trusted ingress verification failed: " + message)


check(
    'static let publicIngressServer = "mail.xingyanmail.site:443"' in API,
    "the client must default to the publicly trusted ingress",
)
check(
    'static let publicIngressPath = "/xy"' in API,
    "the trusted ingress must use its isolated API path",
)
check(
    '"mail.xingyanmail.site"' in API,
    "the public ingress host must be included in trusted hosts",
)
check(
    "if SecTrustEvaluateWithError(trust, nil) {\n            return true\n        }" in API,
    "the session delegate must accept valid system certificate chains",
)
check(
    "pinnedCertificate.contains(digest)" in API,
    "the direct Cell endpoint must retain certificate pinning",
)
check(
    "API.shared.realtimePathPrefix" in REALTIME,
    "realtime WebSocket URLs must preserve the trusted ingress path",
)
check(
    "NSAllowsArbitraryLoads</key><false/>" in INFO,
    "the publicly trusted ingress must not rely on global ATS relaxation",
)

print("trusted-ingress: passed")
