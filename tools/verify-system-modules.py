#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PAYMENT = (ROOT / "Modules" / "PaymentModule" / "PaymentModule.swift").read_text(
    encoding="utf-8"
)
MUSIC = (ROOT / "Modules" / "MusicModule" / "MusicModule.swift").read_text(
    encoding="utf-8"
)
GAME = (ROOT / "Modules" / "GameModule" / "GameModule.swift").read_text(
    encoding="utf-8"
)
BUILD = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)
CHECK = (ROOT / ".github" / "workflows" / "ios-check.yml").read_text(
    encoding="utf-8"
)
LOCAL_BUILD = (ROOT / "mac-build.sh").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("system module verification failed: " + message)


for name, source, marker in [
    ("payment", PAYMENT, "xingyan.payment"),
    ("music", MUSIC, "xingyan.music"),
    ("game", GAME, "xingyan.game"),
]:
    require(
        source.startswith("import Foundation\n")
        and marker in source
        and "import SwiftUI" not in source
        and "import UIKit" not in source
        and "AppState" not in source
        and "API." not in source,
        f"{name} core must stay Foundation-only with no application-state dependency",
    )

require(
    "PaymentMoney" in PAYMENT
    and "PaymentTransferLifecycle" in PAYMENT
    and "PaymentApplePayLayout" in PAYMENT
    and "PaymentReceiptModel" in PAYMENT,
    "payment module must own money, lifecycle, Apple Pay layout, and receipt semantics",
)
require(
    "MusicPlaybackState" in MUSIC
    and "MusicPlaybackPolicy" in MUSIC
    and "preferredForwardBuffer" in MUSIC,
    "music module must own playback state and buffering policy",
)
require(
    "GameRuntimeBudget" in GAME
    and "GameFocusPolicy" in GAME
    and "shouldAutoPlay" in GAME,
    "game module must own runtime budgets and focused autoplay policy",
)

for manifest in [BUILD, CHECK, LOCAL_BUILD]:
    require(
        "XingyanPaymentCore" in manifest
        and "XingyanMusicCore" in manifest
        and "XingyanGameCore" in manifest
        and "Modules/PaymentModule/PaymentModule.swift" in manifest
        and "Modules/MusicModule/MusicModule.swift" in manifest
        and "Modules/GameModule/GameModule.swift" in manifest,
        "all build paths must compile the three independent modules",
    )

require(
    "import PaymentModule" in (ROOT / "Sources" / "TransferFlow.swift").read_text(
        encoding="utf-8"
    )
    and "import MusicModule" in (ROOT / "Sources" / "SystemMusicKernel.swift").read_text(
        encoding="utf-8"
    )
    and "import GameModule" in (ROOT / "Sources" / "GameRuntime.swift").read_text(
        encoding="utf-8"
    ),
    "the app shell must consume modules through public imports",
)

print("system-modules: passed")
