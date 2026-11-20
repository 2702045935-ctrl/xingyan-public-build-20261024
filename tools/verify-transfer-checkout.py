#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TRANSFER = (ROOT / "Sources" / "TransferFlow.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("transfer checkout verification failed: " + message)


require(
    "private var faceConfirmPanel" in TRANSFER
    and 'Text(Tr("使用面容 ID 确认"))' in TRANSFER
    and 'Text(Tr("改用支付密码"))' in TRANSFER
    and "usePassword" in TRANSFER,
    "checkout must offer a primary biometric action with an explicit password fallback",
)
require(
    "NativePremiumGlassMaterial(dark: scheme == .dark)" in TRANSFER
    and "TopRounded(radius: L.paySheetRadius)" in TRANSFER
    and "max(34, L.safeBottom)" in TRANSFER,
    "checkout sheet must use native material, continuous corners and safe-area spacing",
)
require(
    "PayDotField(count: password.count" in TRANSFER
    and "PayKeypadView(busy: busy" in TRANSFER
    and "facePay()" in TRANSFER,
    "password and biometric payment paths must remain functional",
)
require(
    "python3 tools/verify-transfer-checkout.py" in WORKFLOW,
    "transfer checkout regression must run in the iOS gate",
)

print("transfer-checkout: passed")
