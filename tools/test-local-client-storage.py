from __future__ import annotations

import json
import sqlite3
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SWIFT = ROOT / "Sources" / "LocalDatabase.swift"
STRESS_CONFIG = ROOT / "Sources" / "StressTestConfiguration.swift"
STRESS_FIXTURES = {
    "ChatStressFixture.swift": "StressTestConfiguration.chatCount",
    "MessageStressFixture.swift": "StressTestConfiguration.messageCount",
    "MomentStressFixture.swift": "StressTestConfiguration.momentCount",
}


def schema_from_swift() -> str:
    source = SWIFT.read_text(encoding="utf-8")
    start = source.index("CREATE TABLE IF NOT EXISTS local_messages")
    end = source.index("PRAGMA user_version = 1;", start)
    return source[start:end] + "PRAGMA user_version = 1;"


def assert_equal(actual: object, expected: object, label: str) -> None:
    if actual != expected:
        raise AssertionError(f"{label}: expected {expected!r}, got {actual!r}")


def main() -> None:
    config_text = STRESS_CONFIG.read_text(encoding="utf-8")
    for key in (
        "XINGYAN_STRESS_PROFILE",
        "XINGYAN_CHAT_STRESS",
        "XINGYAN_MESSAGE_STRESS",
        "XINGYAN_MOMENT_STRESS",
        "XINGYAN_STRESS_GROUPS",
        "XINGYAN_STRESS_MEMBERS",
    ):
        if key not in config_text:
            raise AssertionError(f"missing stress switch: {key}")
    if "min(100_000, number)" not in config_text:
        raise AssertionError("stress cap must be 100k")
    for filename, marker in STRESS_FIXTURES.items():
        text = (ROOT / "Sources" / filename).read_text(encoding="utf-8")
        if marker not in text:
            raise AssertionError(f"{filename}: does not use shared stress configuration")

    with tempfile.TemporaryDirectory(prefix="xingyan-local-db-") as directory:
        db = sqlite3.connect(Path(directory) / "state.sqlite3")
        db.execute("PRAGMA journal_mode=WAL")
        db.execute("PRAGMA synchronous=FULL")
        db.executescript(schema_from_swift())

        message_sql = """
            INSERT INTO local_messages
                (chat_id, message_id, client_id, seq, created_at, payload, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(chat_id, message_id) DO UPDATE SET
                client_id = excluded.client_id,
                seq = excluded.seq,
                created_at = excluded.created_at,
                payload = excluded.payload,
                updated_at = excluded.updated_at
        """
        with db:
            for seq in range(1, 5003):
                db.execute(
                    message_sql,
                    (
                        "chat-1",
                        f"m-{seq}",
                        f"client-{seq}",
                        seq,
                        f"2026-11-16T00:{seq // 60:02d}:{seq % 60:02d}Z",
                        json.dumps({"id": f"m-{seq}"}).encode(),
                        seq,
                    ),
                )
            db.execute(
                """
                DELETE FROM local_messages
                WHERE chat_id = ?
                  AND message_id NOT IN (
                    SELECT message_id
                    FROM local_messages
                    WHERE chat_id = ?
                    ORDER BY created_at DESC, seq DESC, message_id DESC
                    LIMIT 5000
                  )
                """,
                ("chat-1", "chat-1"),
            )

        count, first_seq = db.execute(
            "SELECT COUNT(*), MIN(seq) FROM local_messages WHERE chat_id = ?",
            ("chat-1",),
        ).fetchone()
        assert_equal(count, 5000, "message retention count")
        assert_equal(first_seq, 3, "oldest retained sequence")

        outbox_sql = """
            INSERT INTO local_outbox
                (client_id, chat_id, kind, content, mentions_json, quote_json,
                 failure_reason, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(client_id) DO UPDATE SET
                chat_id = excluded.chat_id,
                kind = excluded.kind,
                content = excluded.content,
                mentions_json = excluded.mentions_json,
                quote_json = excluded.quote_json,
                failure_reason = excluded.failure_reason,
                created_at = excluded.created_at,
                updated_at = excluded.updated_at
        """
        with db:
            db.execute("DELETE FROM local_outbox WHERE chat_id = ?", ("chat-1",))
            db.execute(outbox_sql, (
                "pending-1", "chat-1", "text", "offline message", "[]",
                None, None, 100.0, 100.0,
            ))
            db.execute(outbox_sql, (
                "pending-1", "chat-1", "text", "offline message", "[]",
                None, "network", 100.0, 101.0,
            ))

        pending = db.execute(
            """
            SELECT content, failure_reason
            FROM local_outbox
            WHERE client_id = ?
            """,
            ("pending-1",),
        ).fetchone()
        assert_equal(pending, ("offline message", "network"), "outbox upsert")

        sync_sql = """
            INSERT INTO local_sync_state (state_key, value, updated_at)
            VALUES (?, ?, ?)
            ON CONFLICT(state_key) DO UPDATE SET
                value = excluded.value,
                updated_at = excluded.updated_at
        """
        with db:
            db.execute(sync_sql, ("messageEvents:user", "10", 100.0))
            db.execute(sync_sql, ("messageEvents:user", "20", 101.0))
        cursor = db.execute(
            "SELECT value FROM local_sync_state WHERE state_key = ?",
            ("messageEvents:user",),
        ).fetchone()
        assert_equal(cursor, ("20",), "sync cursor upsert")

        integrity = db.execute("PRAGMA integrity_check").fetchone()[0]
        assert_equal(integrity, "ok", "sqlite integrity")
        db.close()

    print("Local client SQLite storage tests passed.")


if __name__ == "__main__":
    main()
