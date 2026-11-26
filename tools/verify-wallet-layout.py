#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CARDS = (ROOT / "Sources" / "CardsView.swift").read_text(encoding="utf-8")
PAY = (ROOT / "Sources" / "PaymentUI.swift").read_text(encoding="utf-8")
PAY_SHEET = (ROOT / "Sources" / "XingyanPay.swift").read_text(encoding="utf-8")
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
    and "private struct PayPrimaryActionPressStyle" in PAY
    and "Color.dyn(0x000000, 0xFFFFFF)" in PAY
    and "Color.dyn(0xFFFFFF, 0x000000)" in PAY,
    "Star Pay home must use Apple Wallet's high-contrast compact pay action",
)
require(
    "private var appleWalletHeader" in PAY
    and "Text(name)\n                .font(pf(34, .bold))" in PAY
    and 'Image(systemName: "plus")' in PAY
    and "private func quickActionRow" in PAY
    and 'quickActionRow(Tr("卡包")' in PAY
    and "CardsView()" in PAY
    and 'quickActionRow(Tr("支付安全")' in PAY
    and 'quickActionRow(Tr("虚拟卡")' in PAY,
    "Star Pay must use a large Wallet title and grouped account rows",
)
require(
    "private struct StarPayGuideView" in PAY
    and "starpay.guide.seen.v2" in PAY
    and "TabView(selection: $page)" in PAY
    and "开始使用" in PAY,
    "Star Pay must provide a first-use Wallet guide with persistent completion",
)
require(
    "wallet.deck.tip.seen.v2" in CARDS
    and "private var walletDeckTip" in CARDS
    and "deckTipSeen = true" in CARDS,
    "multi-card wallet guidance must appear once and dismiss after the first deck interaction",
)
require(
    "amountBlock\n                    cardFace\n                    applePayPaymentDetails" in PAY_SHEET
    and "private var applePayPaymentDetails" in PAY_SHEET
    and "PayDetailRow(title: Tr(\"付款方式\")" in PAY_SHEET
    and "PayDetailRow(title: Tr(\"安全验证\")" in PAY_SHEET
    and "ApplePayAuthorizationButtonStyle(enabled: !busy)" in PAY_SHEET,
    "the payment sheet must follow Apple Pay amount, card, details and authorization order",
)
require(
    "paymentHero\n                    paymentPrimaryActions\n                    transactionFeed" in PAY
    and "transactionFeed\n\n                    if loading" in PAY
    and "quickActions\n                    ledgerSummaryStrip" in PAY,
    "Star Pay home must follow Wallet hierarchy: card, payment action, transactions, then utilities",
)
require(
    "python3 tools/verify-wallet-layout.py" in WORKFLOW,
    "wallet layout regression must run in the iOS gate",
)

print("wallet-layout: passed")
