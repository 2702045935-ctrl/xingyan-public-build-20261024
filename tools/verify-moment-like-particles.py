#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CARD = (ROOT / "Sources" / "MomentFeedCard.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("moment like particles verification failed: " + message)


require(
    "struct MomentLikeParticleBurst: View" in CARD
    and "ForEach(0..<(reduceMotion ? 6 : 14)" in CARD
    and ".easeOut(duration: 0.52)" in CARD
    and ".allowsHitTesting(false)" in CARD,
    "likes must use a short bounded particle burst that cannot intercept touches",
)
require(
    "UIImpactFeedbackGenerator(style: .light)" in CARD
    and "likeBurst += 1" in CARD
    and "MomentLikeParticleBurst(seed: likeBurst)" in CARD
    and "accessibilityReduceMotion" in CARD,
    "particle feedback must be tied to a new like and respect Reduce Motion",
)
require(
    "python3 tools/verify-moment-like-particles.py" in WORKFLOW,
    "moment like particle regression must run in the iOS gate",
)

print("moment-like-particles: passed")
