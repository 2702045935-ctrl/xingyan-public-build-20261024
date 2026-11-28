#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SECURITY = (ROOT / "Sources" / "AccountSecurityView.swift").read_text(
    encoding="utf-8"
)
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)
ACCOUNT_HOME = SECURITY.split("struct ChangePasswordSheet", 1)[0]


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("account security system verification failed: " + message)


require(
    "private var securityOverview" in SECURITY
    and "private func securitySection" in SECURITY
    and "private func securityRow" in SECURITY
    and "RoundedRectangle(cornerRadius: 18" in SECURITY
    and 'Text(Tr("账号保护"))' in SECURITY
    and 'Tr("账号与登录")' in SECURITY
    and 'Tr("身份与支付")' in SECURITY
    and 'Tr("应用保护")' in SECURITY
    and 'Tr("登录设备")' in SECURITY
    and 'Tr("安全学习")' in SECURITY,
    "account security must use a system-settings hierarchy with overview and grouped sections",
)
require(
    "AccountSafetyCenterView()" in SECURITY
    and "ChangePasswordSheet()" in SECURITY
    and "RealNameView()" in SECURITY
    and "PayPasswordView()" in SECURITY
    and "GestureSetupView()" in SECURITY
    and "VoiceLockSetupView()" in SECURITY
    and "LoginDevicesView()" in SECURITY
    and "API.shared.logoutOtherDevices()" in SECURITY
    and "API.shared.realNameStatus()" in SECURITY
    and "API.shared.hasPayPassword()" in SECURITY,
    "visual redesign must preserve every security route and backend check",
)
require(
    "List {" not in ACCOUNT_HOME
    and ".listStyle(.insetGrouped)" not in ACCOUNT_HOME
    and ".presentationDetents([.fraction(0.88), .large])" in ACCOUNT_HOME
    and "python3 tools/verify-account-security-system.py" in WORKFLOW,
    "the old generic List layout must be replaced and gated by the iOS verification suite",
)

print("account-security-system: passed")
