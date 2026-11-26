#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CLIENT = (ROOT / "Sources" / "FeatureManifest.swift").read_text(
    encoding="utf-8"
)
DISCOVER = (ROOT / "Sources" / "DiscoverView.swift").read_text(
    encoding="utf-8"
)
SERVER = (ROOT / "server" / "server.js").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("feature manifest verification failed: " + message)


require(
    'parts[0] === \'ui-manifest\'' in SERVER
    and "crypto.sign(" in SERVER
    and "FEATURE_MANIFEST_KEY_ID = 'fm-v1'" in SERVER
    and "expiresAt: new Date(now + 5 * 60 * 1000)" in SERVER,
    "server must issue short-lived Ed25519-signed feature manifests",
)
require(
    "Curve25519.Signing.PublicKey" in CLIENT
    and "isValidSignature" in CLIENT
    and "FeatureManifestError.rolledBack" in CLIENT
    and "AES.GCM.seal" in CLIENT
    and "Keychain.setDeviceBound" in CLIENT,
    "client must verify, expiration-check and encrypt-cache the manifest",
)
require(
    "API.shared.signedFeatureManifest()" in DISCOVER
    and "FeatureManifestStore.cachedItems()" in DISCOVER
    and 'action == "map"' not in DISCOVER,
    "world entries must come from the signed manifest without map auto-injection",
)
require(
    "python3 tools/verify-feature-manifest.py" in WORKFLOW,
    "feature manifest regression must run in the iOS gate",
)

print("feature-manifest: passed")
