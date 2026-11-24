#!/usr/bin/env python3
"""Static gate for the independent banking-grade audit center."""

from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]


def require(path: str, needles: list[str]) -> None:
    text = (ROOT / path).read_text(encoding="utf-8")
    missing = [needle for needle in needles if needle not in text]
    if missing:
        raise AssertionError(f"{path}: missing {missing}")


def main() -> int:
    require(
        "server/lib/banking-audit.js",
        [
            "createHmac('sha256'",
            "prevHash",
            "bad-hmac",
            "fs.fsyncSync",
            "withLock",
            "manifestMac",
            "verify()",
            "this.seal",
        ],
    )
    require(
        "server/server.js",
        [
            "BankingAuditLog",
            "ensureBankingAudit",
            "audit/secure",
            "audit/integrity",
            "audit/export",
            "X-Request-ID",
            "userAgent",
            "审计写失败会抛错",
            "sealSecureStoreValue(BANK_AUDIT_FILE",
        ],
    )
    require(
        "server/test/banking-audit.test.js",
        [
            "broken-chain",
            "bad-hmac",
            "manifestMac",
            "banking-audit: passed",
        ],
    )
    center = ROOT.parent / "xingyan-audit-center"
    if center.exists():
        for relative in [
            "lib/main.dart",
            "lib/audit_api.dart",
            "lib/audit_models.dart",
            "lib/audit_export_io.dart",
        ]:
            path = center / relative
            if not path.exists():
                raise AssertionError(f"audit center missing {relative}")
        main_text = (center / "lib/main.dart").read_text(encoding="utf-8")
        for label in ["审计总览", "操作审计", "金融审计", "AML 风控", "完整性校验"]:
            if label not in main_text:
                raise AssertionError(f"audit center missing page {label}")
        api_text = (center / "lib/audit_api.dart").read_text(encoding="utf-8")
        for route in ["/api/ops/audit/secure", "/api/ops/audit/export"]:
            if route not in api_text:
                raise AssertionError(f"audit center missing route {route}")
    print("banking audit gate: passed")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"banking audit gate failed: {error}", file=sys.stderr)
        raise
