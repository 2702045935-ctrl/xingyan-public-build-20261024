#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SERVER = (ROOT / "server" / "server.js").read_text(encoding="utf-8")
APP = (ROOT / "Sources" / "App.swift").read_text(encoding="utf-8")
PUSH = (ROOT / "Sources" / "PushCenter.swift").read_text(encoding="utf-8")
REALTIME = (ROOT / "Sources" / "Realtime.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("push multi-device verification failed: " + message)


require(
    "parts[0] === 'sync' && parts[1] === 'state'" in SERVER
    and "parts[0] === 'sync' && parts[1] === 'ack'" in SERVER
    and "messageReliability.deviceCursor(user.id, deviceId, chat.id)" in SERVER
    and "messageReliability.ackDevice(user.id, deviceId, chatId, requested)" in SERVER,
    "server must expose authoritative device sync state and idempotent acknowledgements",
)
require(
    "const readSeq = Math.min(lastSeq" in SERVER
    and "deliveredSeq: 0" not in SERVER.split("parts[0] === 'sync'")[1][:5000],
    "account-wide reads must be shared while delivery cursors stay device scoped",
)
require(
    "recordEvent('chat.removed'" in SERVER
    and "recordEvent('friend.removed'" in SERVER
    and "case \"chat.removed\":" in APP
    and "case \"friend.removed\":" in APP
    and "var ownerId: String?" in (ROOT / "Sources" / "API.swift").read_text(encoding="utf-8")
    and "var targetId: String?" in (ROOT / "Sources" / "API.swift").read_text(encoding="utf-8"),
    "chat and friend tombstones must survive offline multi-device recovery",
)
require(
    "headers['apns-collapse-id'] = String(collapseId).slice(0, 64)" in SERVER
    and "'thread-id': opts.chatId || opts.kind || 'chris'" in SERVER
    and "opts.collapse || ''" in SERVER,
    "APNs collapse and thread identifiers must be sent as protocol headers/aps fields",
)
require(
    "if (deviceId) exist.deviceId = deviceId" in SERVER
    and "list.push({ token, env, platform, deviceId, updatedAt: now() })" in SERVER,
    "push registrations must bind tokens to a device identity",
)
require(
    "func syncDeviceChats(" in APP
    and "func syncMessageEvents()" in APP
    and "await self?.syncDeviceChats()" in APP
    and "await self?.syncMessageEvents()" in APP,
    "client reconnect and foreground recovery must pull both message pages and event tombstones",
)
require(
    "func registerPushToken(_ token: String, sandbox: Bool)" in (
        ROOT / "Sources" / "API.swift"
    ).read_text(encoding="utf-8")
    and "didRegisterForRemoteNotificationsWithDeviceToken" in PUSH
    and "requestAuthorization(options: [.alert, .sound, .badge])" in PUSH,
    "push token registration must preserve alert, sound and badge delivery",
)
require(
    ".onChange(of: scenePhase)" in APP
    and "if phase == .active && app.me != nil" in APP
    and "syncDeviceChats()" in APP
    and "syncMessageEvents()" in APP,
    "foreground recovery must reconcile multi-device state",
)
require(
    "node server/test/device-sync-state.test.js" in WORKFLOW
    and "python3 tools/verify-push-multidevice.py" in WORKFLOW,
    "push and multi-device regression must run in the iOS gate",
)

print("push-multidevice: passed")
