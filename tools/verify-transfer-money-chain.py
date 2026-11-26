#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SERVER = (ROOT / "server" / "server.js").read_text(encoding="utf-8")
API = (ROOT / "Sources" / "API.swift").read_text(encoding="utf-8")
REALTIME = (ROOT / "Sources" / "Realtime.swift").read_text(encoding="utf-8")
CHAT = (ROOT / "Sources" / "ChatDetailView.swift").read_text(encoding="utf-8")
BILL = (ROOT / "Sources" / "BillView.swift").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build-ios.yml").read_text(
    encoding="utf-8"
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit("transfer money chain verification failed: " + message)


require(
    "const charge = applyMoney(user, -amount" in SERVER
    and "status: 'pending'" in SERVER
    and "const sent = deliverMessage(user, chat.id, 'transfer'" in SERVER
    and "转账发不出去退回" in SERVER
    and "idemBegin(user, body, 'transfer')" in SERVER,
    "send must debit once, persist a pending transfer, and roll back only when delivery fails",
)
require(
    "tr.toId !== user.id" in SERVER
    and "tr.status === 'received'" in SERVER
    and "alreadyReceived: true" in SERVER
    and "transaction: 'received'" not in SERVER
    and "tr.status = 'received'" in SERVER
    and "broadcastTransfer(tr, 'received')" in SERVER,
    "claim must be recipient-only, idempotent, server-authoritative, and broadcast",
)
require(
    "tr.toId !== user.id" in SERVER
    and "5 * 60 * 60 * 1000" in SERVER
    and "refundTransfer(tr.id" in SERVER
    and "broadcastTransfer(tr, 'refunded')" in SERVER,
    "refund must remain recipient-only, time-bounded, and update both sides",
)
require(
    "function syncTransferMessage(t)" in SERVER
    and "msg.content = transferSnapshot(t)" in SERVER
    and "[t.fromId, t.toId].forEach" in SERVER,
    "the canonical message snapshot must be persisted and broadcast to payer and payee",
)
require(
    '"/api/transfers/\\(id)/claim"' in API
    and '"/api/transfers/\\(id)/refund"' in API
    and "var refundedBy: String?" in API
    and "var transfer: API.TransferPayment?" in REALTIME
    and "payments = try? JSONDecoder().decode(API.TransferPayment.self" not in REALTIME
    and "ev.transfer = payment" in REALTIME,
    "client claim/refund APIs and full realtime transfer snapshots must stay wired",
)
require(
    "applyTransferRealtimeUpdate(ev)" in CHAT
    and "private func applyTransferRealtimeUpdate(_ event: PushEvent)" in CHAT
    and "messages[index].content = body" in CHAT
    and "event.type == \"transfer\"" in BILL
    and "live = TransferInfo(payment: payment)" in BILL,
    "open chat cards and transfer details must update from the server event, not local guesses",
)

require(
    "python3 tools/verify-transfer-money-chain.py" in WORKFLOW,
    "the transfer money chain must run in the iOS gate",
)

print("transfer-money-chain: passed")
