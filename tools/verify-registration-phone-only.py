#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
APP = (ROOT / "Sources" / "App.swift").read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("registration phone-only verification failed: " + message)


require(
    "@State private var mode: Mode = .account" in APP,
    "registration must open on the supported Xingyan account flow",
)
require(
    'registrationTab(Tr("星言号注册"), selected: mode == .account)' in APP,
    "the Xingyan account registration tab must be visible",
)
require(
    "smsCode: code" in APP
    and "requirePhoneCode: true" in APP,
    "account registration must keep the SMS verification requirement",
)

print("registration-phone-only: passed")
