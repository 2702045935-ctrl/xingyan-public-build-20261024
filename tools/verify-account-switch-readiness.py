#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
APP = (ROOT / "Sources" / "App.swift").read_text(encoding="utf-8")
SWITCH = (ROOT / "Sources" / "SwitchAccountView.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("account-switch-readiness verification failed: " + message)


start = APP.index("func quickLogin(")
end = APP.index("func contact(for id: String)", start)
block = APP[start:end]
require(
    "let cachedChats = LocalStore.cachedChatList(userId: user.id)" in block
    and "if !cachedChats.isEmpty { chats = cachedChats }" in block,
    "the target account's cached conversation list must hydrate before navigation",
)
require(
    "if switchingAccount,\n"
    "           let username,\n"
    "           !username.isEmpty,\n"
    "           let cached = AppState.cachedUser(username: username)" in block
    and "me = cached" in block
    and "contacts = Self.cachedContacts(userId: cached.id)" in block
    and block.index("me = cached") < block.index("let epoch = accountEpoch")
    and "if let session = try? await API.shared.session()" in block,
    "account switching must render cached identity before session verification",
)
require(
    "if switchingAccount {" in block
    and "Realtime.shared.start()" in block
    and "Task {" in block
    and block.index("if switchingAccount {")
    < block.index("Task {", block.index("if switchingAccount {"))
    < block.index("return true", block.index("if switchingAccount {"))
    < block.rindex("await refreshAll()"),
    "account switching must return after cached chats and refresh the home data in background",
)
require(
    "let ok = await app.quickLogin(token: saved," in SWITCH
    and "switchingAccount: true" in SWITCH
    and "if ok {\n                dismiss()" in SWITCH,
    "the account picker must dismiss as soon as the target identity is ready",
)
require(
    "python3 tools/verify-account-switch-readiness.py" in WORKFLOW,
    "account switch responsiveness must run in the iOS gate",
)

print("account-switch-readiness: passed")
