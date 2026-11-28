#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TRANSFER = (ROOT / "Sources" / "TransferFlow.swift").read_text(encoding="utf-8")
CHAT = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")
PAY_CODE = (ROOT / "Sources" / "PayCode.swift").read_text(encoding="utf-8")
PAYMENT = (ROOT / "Sources" / "PaymentUI.swift").read_text(encoding="utf-8")
API = (ROOT / "Sources" / "API.swift").read_text(encoding="utf-8")
SERVER = (ROOT / "server" / "server.js").read_text(encoding="utf-8")
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
    and ".overlay {\n            if busy {\n                PayBusyOverlay(text: \"正在转账\")"
    in TRANSFER
    and "ProgressView().padding(18)" not in TRANSFER,
    "checkout must expose one blocking progress state above the password sheet",
)
require(
    "PayDotField(count: password.count" in TRANSFER
    and "PayKeypadView(" in TRANSFER
    and "busy: busy" in TRANSFER
    and "tapPay(key)" in TRANSFER
    and "facePay()" in TRANSFER,
    "password and biometric payment paths must remain functional",
)
require(
    "enum PayBankVisual" in PAYMENT
    and "struct PayBankBackdrop: View" in PAYMENT
    and "struct PayBankCardHeader: View" in PAYMENT
    and "func payBankCardSurface" in PAYMENT
    and "private var transferDeskBackdrop" in TRANSFER
    and "PayBankBackdrop()" in TRANSFER
    and "PayBankVisual.surface" in TRANSFER
    and '"STAR PAY BANKING"' in TRANSFER
    and "amount > 0 ? transferBlue" in TRANSFER
    and "PayBankBackdrop()" in PAY_CODE
    and "PayBankVisual.surface" in PAY_CODE,
    "transfer and receive surfaces must share one bank-style design system",
)
require(
    "let result = try await API.shared.transfer(" in TRANSFER
    and "method: method, password: password, face: face)" in TRANSFER
    and "onPaid(result.message, result.transfer)" in TRANSFER
    and "var message: Message?" in API
    and "message: sent.message" in SERVER
    and "message: transferMessage" in SERVER
    and "onPaid: { message, transfer in" in CHAT
    and "transfer.flatMap(makeTransferMessage)" in CHAT
    and "private func makeTransferMessage(_ transfer: API.TransferPayment)" in CHAT
    and "API.shared.receiveCode(amount: amount)" in PAY_CODE
    and "private var receiveBankCard" in PAY_CODE
    and '"STAR PAY RECEIVE"' in PAY_CODE
    and "QRCanvas(rows: rows)" in PAY_CODE,
    "bank styling must not alter transfer submission or receive-code generation",
)
require(
    "python3 tools/verify-transfer-checkout.py" in WORKFLOW,
    "transfer checkout regression must run in the iOS gate",
)

print("transfer-checkout: passed")
