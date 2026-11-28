#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PAYMENT = (ROOT / "Sources" / "PaymentUI.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("payment gold card verification failed: " + message)


require(
    "struct StarPayGoldCardSurface: View" in PAYMENT
    and "struct StarPayGoldCardFace: View" in PAYMENT
    and "StarPayGoldBrushedMetal" in PAYMENT
    and ".compositingGroup()" in PAYMENT,
    "gold card must use a dedicated layered metal surface instead of a tinted black card",
)
require(
    "StarPayPhysicalCardSurface(radius: 28)" in PAYMENT
    and "showGoldCard: goldUnlocked" in PAYMENT
    and "if showGoldCard {" in PAYMENT
    and "private struct PayGoldCardDetailView" in PAYMENT
    and "private var goldCardSection" in PAYMENT,
    "normal users must keep the black card while eligible users can open a separate gold-card page",
)
require(
    "private static let goldThreshold = 50_000.0" in PAYMENT
    and "adminGoldPreview" in PAYMENT
    and "app.me?.ops == true" in PAYMENT
    and "普通用户累计消费满" in PAYMENT,
    "gold card must be admin-preview first and later unlock from cumulative spending",
)
require(
    "python3 tools/verify-payment-gold-card.py" in WORKFLOW,
    "gold card regression must run in the iOS build gate",
)

print("payment-gold-card: passed")
