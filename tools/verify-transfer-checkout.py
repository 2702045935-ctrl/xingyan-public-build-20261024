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
    and "usePassword" in TRANSFER
    and "AppleCheckoutButtonStyle()" in TRANSFER,
    "checkout must offer a primary biometric action with an explicit password fallback",
)
require(
    ".sheet(isPresented: $showPay)" in TRANSFER
    and ".presentationDetents([.large])" in TRANSFER
    and ".interactiveDismissDisabled(busy)" in TRANSFER
    and "private var paySheetHeader" in TRANSFER
    and "max(18, L.safeBottom)" in TRANSFER,
    "checkout must use a native system sheet with safe pinned authorization controls",
)
require(
    "private var checkoutHero" in TRANSFER
    and "private var checkoutSummaryCard" in TRANSFER
    and "private var paymentTrustLine" in TRANSFER
    and "private func checkoutSurface" in TRANSFER
    and "checkoutDetailsExpanded" in TRANSFER
    and 'Tr("付款详情")' in TRANSFER,
    "checkout must use an Apple Pay-style amount, method, expandable details and trust hierarchy",
)
require(
    "private var methodSheet" in TRANSFER
    and "NavigationStack" in TRANSFER
    and ".presentationDetents([.medium, .large])" in TRANSFER
    and "Image(systemName: key == \"xypay\"" in TRANSFER
    and "PayVisual.tint.opacity(scheme == .dark ? 0.14 : 0.08)" in TRANSFER
    and "Image(systemName: \"checkmark\")" in TRANSFER,
    "payment method selection must use a native, selectable Apple-style sheet",
)
require(
    "PayBusyOverlay(text: \"正在转账\")" in TRANSFER
    and TRANSFER.count("PayBusyOverlay(text: \"正在转账\")") == 1
    and "ProgressView().padding(18)" not in TRANSFER,
    "checkout must expose exactly one blocking progress state",
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
