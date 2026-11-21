#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CARDS = (ROOT / "Sources" / "CardsView.swift").read_text(encoding="utf-8")
PAY = (ROOT / "Sources" / "PaymentUI.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("wallet layout verification failed: " + message)


require(
    "private var focusedCardID: String?" in CARDS
    and "walletCardStack(live)" in CARDS
    and "private var walletCardPeek: CGFloat { 42 }" in CARDS
    and "ZStack(alignment: .top)" in CARDS
    and "zIndex(Double(ordered.count - index))" in CARDS,
    "available wallet cards must render as an overlapping Apple Wallet-style deck",
)
require(
    "if index == 0 {\n                        open = card" in CARDS
    and "focusedCardID = card.id" in CARDS
    and "private func walletCardFace" in CARDS
    and "maskedCardCode" in CARDS,
    "tapping a back card must focus it before opening its detail",
)
require(
    "paymentPrimaryActions" in PAY
    and "PayCodePage()" in PAY
    and "ReceiveCodePage()" in PAY
    and "private struct PayPrimaryActionPressStyle" in PAY,
    "Star Pay home must lead with dedicated pay and receive actions",
)
require(
    'quickAction(Tr("卡包"), "rectangle.stack.fill", PayVisual.gold)' in PAY
    and "CardsView()" in PAY
    and 'quickAction(Tr("收付款"), "qrcode", PayVisual.tint)' not in PAY,
    "Star Pay quick actions must open the wallet and must not duplicate the primary pay action",
)
require(
    "paymentHero\n                    paymentPrimaryActions\n                    quickActions" in PAY,
    "Star Pay home must follow Wallet hierarchy: card, primary actions, then utilities",
)
require(
    "python3 tools/verify-wallet-layout.py" in WORKFLOW,
    "wallet layout regression must run in the iOS gate",
)

print("wallet-layout: passed")
