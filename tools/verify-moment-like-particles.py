#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CARD = (ROOT / "Sources" / "NativeMomentRowCell.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("moment like particles verification failed: " + message)


require(
    "NativeMomentLikeParticleBurst: UIView" in CARD
    and "let tier = DevicePerformanceProfile.shared.tier" in CARD
    and "tier == .high ? 14" in CARD
    and "tier == .balanced ? 10 : 7" in CARD
    and "withDuration: reduceMotion ? 0.22 : 0.52" in CARD
    and "likeBurst.isUserInteractionEnabled = false" in CARD,
    "likes must use a native bounded particle burst that cannot intercept touches",
)
require(
    "UIImpactFeedbackGenerator(style: .light)" in CARD
    and "likeBurst.burst()" in CARD
    and "UIAccessibility.isReduceMotionEnabled" in CARD,
    "particle feedback must be tied to a new like and respect Reduce Motion",
)
require(
    "python3 tools/verify-moment-like-particles.py" in WORKFLOW,
    "moment like particle regression must run in the iOS gate",
)

print("moment-like-particles: passed")
