#!/usr/bin/env python3
import json
import plistlib
import re
import sys
import zipfile
from pathlib import Path


SECRET_PATTERNS = {
    "rsa_private": rb"BEGIN RSA PRIVATE KEY",
    "private_key": rb"BEGIN PRIVATE KEY",
    "openssh_private": rb"BEGIN OPENSSH PRIVATE KEY",
    "aws_access_key": rb"AKIA[0-9A-Z]{16}",
    "aliyun_access_key": rb"LTAI[0-9A-Za-z]{12,}",
    "openai_key": rb"sk-[A-Za-z0-9]{20,}",
    "github_pat": rb"github_pat_[A-Za-z0-9_]{20,}",
    "bearer_literal": rb"Bearer [A-Za-z0-9._-]{20,}",
    "jwt_like": rb"eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}",
}


def fail(message: str) -> None:
    raise SystemExit("IPA audit failed: " + message)


def main() -> None:
    if len(sys.argv) != 2:
        fail("usage: audit-ipa.py /path/to/app.ipa")
    ipa = Path(sys.argv[1])
    if not ipa.is_file() or ipa.stat().st_size < 1024:
        fail("IPA is missing or empty")

    with zipfile.ZipFile(ipa) as archive:
        names = archive.namelist()
        apps = {
            name.split("/")[1]
            for name in names
            if name.startswith("Payload/")
            and len(name.split("/")) > 1
            and name.split("/")[1]
        }
        if len(apps) != 1:
            fail("expected exactly one app bundle in Payload")
        app_name = next(iter(apps))
        info_path = f"Payload/{app_name}/Info.plist"
        if info_path not in names:
            fail("Info.plist is missing")
        info = plistlib.loads(archive.read(info_path))
        ats = info.get("NSAppTransportSecurity") or {}
        if ats.get("NSAllowsArbitraryLoads") is not False:
            fail("NSAllowsArbitraryLoads must be false")
        if ats.get("NSAllowsLocalNetworking") is not True:
            fail("NSAllowsLocalNetworking must remain enabled")
        if ats.get("NSAllowsArbitraryLoadsInWebContent") is not True:
            fail("WKWebView needs the scoped web-content exception")

        forbidden = (
            ".dSYM/",
            ".swiftmodule",
            "/Headers/",
            "/Modules/",
            "/PrivateHeaders/",
            ".DS_Store",
            "__MACOSX/",
        )
        leftovers = [
            name for name in names if any(item in name for item in forbidden)
        ]
        if leftovers:
            fail("debug/development files remain: " + ", ".join(leftovers[:5]))

        executable = f"Payload/{app_name}/"
        candidates = [
            name
            for name in names
            if name.startswith(executable)
            and name.count("/") == 2
            and not name.endswith("/")
        ]
        if len(candidates) != 1:
            fail("unable to identify the main executable")
        binary = archive.read(candidates[0])
        if len(binary) < 1_000_000:
            fail("main executable is unexpectedly small")

        findings = {}
        for label, pattern in SECRET_PATTERNS.items():
            count = len(re.findall(pattern, binary, re.I))
            if count:
                findings[label] = count
        if findings:
            fail("possible embedded credentials: " + json.dumps(findings))

        source_paths = len(
            re.findall(rb"(?:/Users/|/home/|Documents/Codex/|Sources/)", binary)
        )
        if source_paths:
            fail(f"binary exposes {source_paths} source/build path fragments")

        printable = re.findall(rb"[ -~]{4,}", binary)
        endpoint_count = len(
            {
                match.group(0)
                for item in printable
                for match in re.finditer(
                    rb"/api/[A-Za-z0-9_?=&/.{}:-]+", item
                )
            }
        )
        swift_type_count = sum(
            1 for item in printable if b"$s" in item or item.startswith(b"_Tt")
        )
        print(
            json.dumps(
                {
                    "ipa_bytes": ipa.stat().st_size,
                    "app": app_name,
                    "binary_bytes": len(binary),
                    "api_paths": endpoint_count,
                    "swift_metadata_strings": swift_type_count,
                    "debug_files": 0,
                    "embedded_credentials": 0,
                    "arbitrary_app_http": False,
                },
                ensure_ascii=False,
            )
        )


if __name__ == "__main__":
    main()
