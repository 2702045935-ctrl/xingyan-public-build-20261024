import Foundation
import SQLite3

private let localSQLiteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Transactional client-side storage for message windows, pending sends and
/// resumable sync cursors. Writes are serialized and use WAL + FULL sync so a
/// process crash cannot leave a half-written outbox or cursor update.
final class LocalDatabase: @unchecked Sendable {
    static let shared = LocalDatabase()

    private let lock = NSRecursiveLock()
    private var database: OpaquePointer?

    private init() {
        open()
    }

    deinit {
        if let database {
            sqlite3_close(database)
        }
    }

    func loadChat(_ chatId: String) -> [Message] {
        guard !chatId.isEmpty else { return [] }
        let payloads = read { db in
            let sql = """
                SELECT payload
                FROM local_messages
                WHERE chat_id = ?
                ORDER BY created_at ASC, seq ASC, message_id ASC
                LIMIT 5000
                """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
                  let statement else { return nil }
            defer { sqlite3_finalize(statement) }
            bind(chatId, to: statement, at: 1)
            var values: [Data] = []
            values.reserveCapacity(512)
            while sqlite3_step(statement) == SQLITE_ROW {
                if let data = blob(statement, column: 0) {
                    values.append(data)
                }
            }
            return values
        } ?? []

        let decoder = JSONDecoder()
        return payloads.compactMap { try? decoder.decode(Message.self, from: $0) }
    }

    @discardableResult
    func saveChat(_ chatId: String, messages: [Message], migrationKey: String) -> Bool {
        guard !chatId.isEmpty, !messages.isEmpty else { return false }
        let tail = Array(messages.suffix(5000))
        let encoder = JSONEncoder()
        let encoded: [(Message, Data)] = tail.compactMap { message in
            guard !message.id.isEmpty,
                  let data = try? encoder.encode(message) else { return nil }
            return (message, data)
        }
        guard !encoded.isEmpty else { return false }
        let now = Date().timeIntervalSince1970

        return write { db in
            let sql = """
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
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
                  let statement else { return false }
            defer { sqlite3_finalize(statement) }

            for (message, payload) in encoded {
                sqlite3_reset(statement)
                sqlite3_clear_bindings(statement)
                bind(chatId, to: statement, at: 1)
                bind(message.id, to: statement, at: 2)
                bindOptional(message.clientId, to: statement, at: 3)
                sqlite3_bind_int64(statement, 4, sqlite3_int64(message.seq ?? 0))
                bind(message.createdAt ?? "", to: statement, at: 5)
                bind(payload, to: statement, at: 6)
                sqlite3_bind_double(statement, 7, now)
                guard sqlite3_step(statement) == SQLITE_DONE else { return false }
            }

            let pruneSQL = """
                DELETE FROM local_messages
                WHERE chat_id = ?
                  AND message_id NOT IN (
                    SELECT message_id
                    FROM local_messages
                    WHERE chat_id = ?
                    ORDER BY created_at DESC, seq DESC, message_id DESC
                    LIMIT 5000
                  )
                """
            var prune: OpaquePointer?
            guard sqlite3_prepare_v2(db, pruneSQL, -1, &prune, nil) == SQLITE_OK,
                  let prune else { return false }
            defer { sqlite3_finalize(prune) }
            bind(chatId, to: prune, at: 1)
            bind(chatId, to: prune, at: 2)
            guard sqlite3_step(prune) == SQLITE_DONE else { return false }
            return setMetadata(db, key: migrationKey, value: "1", now: now)
        }
    }

    func chatNeedsLegacyMigration(_ key: String) -> Bool {
        metadata(key) != "1"
    }

    @discardableResult
    func markChatMigrated(_ key: String) -> Bool {
        write { db in
            setMetadata(db, key: key, value: "1", now: Date().timeIntervalSince1970)
        }
    }

    @discardableResult
    func clearChat(_ chatId: String) -> Bool {
        guard !chatId.isEmpty else { return false }
        return write { db in
            let sql = "DELETE FROM local_messages WHERE chat_id = ?"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
                  let statement else { return false }
            defer { sqlite3_finalize(statement) }
            bind(chatId, to: statement, at: 1)
            return sqlite3_step(statement) == SQLITE_DONE
        }
    }

    func loadOutbox(_ chatId: String) -> [PendingMsg] {
        guard !chatId.isEmpty else { return [] }
        return read { db in
            let sql = """
                SELECT client_id, kind, content, mentions_json, quote_json,
                       failure_reason, created_at
                FROM local_outbox
                WHERE chat_id = ?
                ORDER BY created_at ASC, client_id ASC
                LIMIT 200
                """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
                  let statement else { return nil }
            defer { sqlite3_finalize(statement) }
            bind(chatId, to: statement, at: 1)
            var rows: [PendingMsg] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let id = text(statement, column: 0)
                let kind = text(statement, column: 1)
                let content = text(statement, column: 2)
                guard !id.isEmpty, !kind.isEmpty else { continue }
                let mentions = decodeStringArray(text(statement, column: 3))
                let quote = optionalText(statement, column: 4)
                let failure = optionalText(statement, column: 5)
                let at = Date(timeIntervalSince1970: sqlite3_column_double(statement, 6))
                rows.append(PendingMsg(
                    id: id,
                    kind: kind,
                    content: content,
                    mentions: mentions,
                    quoteJSON: quote,
                    failed: !(failure ?? "").isEmpty,
                    failureReason: failure,
                    at: at
                ))
            }
            return rows
        } ?? []
    }

    @discardableResult
    func saveOutbox(_ chatId: String, messages: [PendingMsg]) -> Bool {
        guard !chatId.isEmpty else { return false }
        let now = Date().timeIntervalSince1970
        return write { db in
            let deleteSQL = "DELETE FROM local_outbox WHERE chat_id = ?"
            var deleteStatement: OpaquePointer?
            guard sqlite3_prepare_v2(db, deleteSQL, -1, &deleteStatement, nil) == SQLITE_OK,
                  let deleteStatement else { return false }
            bind(chatId, to: deleteStatement, at: 1)
            let deleted = sqlite3_step(deleteStatement) == SQLITE_DONE
            sqlite3_finalize(deleteStatement)
            guard deleted else { return false }
            guard !messages.isEmpty else { return true }

            let insertSQL = """
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
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, insertSQL, -1, &statement, nil) == SQLITE_OK,
                  let statement else { return false }
            defer { sqlite3_finalize(statement) }
            for pending in messages.prefix(200) {
                sqlite3_reset(statement)
                sqlite3_clear_bindings(statement)
                bind(pending.id, to: statement, at: 1)
                bind(chatId, to: statement, at: 2)
                bind(pending.kind, to: statement, at: 3)
                bind(pending.content, to: statement, at: 4)
                bind(encodeStringArray(pending.mentions), to: statement, at: 5)
                bindOptional(pending.quoteJSON, to: statement, at: 6)
                bindOptional(pending.failureReason, to: statement, at: 7)
                sqlite3_bind_double(statement, 8, pending.at.timeIntervalSince1970)
                sqlite3_bind_double(statement, 9, now)
                guard sqlite3_step(statement) == SQLITE_DONE else { return false }
            }
            return true
        }
    }

    func syncValue(_ key: String) -> String? {
        guard !key.isEmpty else { return nil }
        return read { db in
            let sql = "SELECT value FROM local_sync_state WHERE state_key = ?"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
                  let statement else { return nil }
            defer { sqlite3_finalize(statement) }
            bind(key, to: statement, at: 1)
            guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
            return text(statement, column: 0)
        }
    }

    @discardableResult
    func setSyncValue(_ key: String, value: String?) -> Bool {
        guard !key.isEmpty else { return false }
        return write { db in
            if let value, !value.isEmpty {
                let sql = """
                    INSERT INTO local_sync_state (state_key, value, updated_at)
                    VALUES (?, ?, ?)
                    ON CONFLICT(state_key) DO UPDATE SET
                        value = excluded.value,
                        updated_at = excluded.updated_at
                    """
                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
                      let statement else { return false }
                defer { sqlite3_finalize(statement) }
                bind(key, to: statement, at: 1)
                bind(value, to: statement, at: 2)
                sqlite3_bind_double(statement, 3, Date().timeIntervalSince1970)
                return sqlite3_step(statement) == SQLITE_DONE
            }

            let sql = "DELETE FROM local_sync_state WHERE state_key = ?"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
                  let statement else { return false }
            defer { sqlite3_finalize(statement) }
            bind(key, to: statement, at: 1)
            return sqlite3_step(statement) == SQLITE_DONE
        }
    }

    private func metadata(_ key: String) -> String? {
        guard !key.isEmpty else { return nil }
        return read { db in
            let sql = "SELECT value FROM local_metadata WHERE meta_key = ?"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
                  let statement else { return nil }
            defer { sqlite3_finalize(statement) }
            bind(key, to: statement, at: 1)
            guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
            return text(statement, column: 0)
        }
    }

    private func open() {
        lock.lock()
        defer { lock.unlock() }
        let url = LocalStore.root.appendingPathComponent("XingyanState.sqlite3")
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try? mutableURL.setResourceValues(values)

        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let result = url.path.withCString {
            sqlite3_open_v2($0, &database, flags, nil)
        }
        guard result == SQLITE_OK, let database else {
            NSLog("[LocalDB] open failed: %@", lastErrorMessage())
            if let database {
                sqlite3_close(database)
                self.database = nil
            }
            return
        }
        sqlite3_busy_timeout(database, 3_000)
        _ = executeUnlocked("PRAGMA journal_mode=WAL")
        _ = executeUnlocked("PRAGMA synchronous=FULL")
        _ = executeUnlocked("PRAGMA foreign_keys=ON")
        _ = executeUnlocked("PRAGMA temp_store=MEMORY")
        _ = executeUnlocked("""
            CREATE TABLE IF NOT EXISTS local_messages (
                chat_id TEXT NOT NULL,
                message_id TEXT NOT NULL,
                client_id TEXT,
                seq INTEGER NOT NULL DEFAULT 0,
                created_at TEXT NOT NULL DEFAULT '',
                payload BLOB NOT NULL,
                updated_at REAL NOT NULL,
                PRIMARY KEY (chat_id, message_id)
            );
            CREATE INDEX IF NOT EXISTS local_messages_order
                ON local_messages(chat_id, created_at, seq, message_id);
            CREATE TABLE IF NOT EXISTS local_outbox (
                client_id TEXT PRIMARY KEY,
                chat_id TEXT NOT NULL,
                kind TEXT NOT NULL,
                content TEXT NOT NULL,
                mentions_json TEXT NOT NULL DEFAULT '[]',
                quote_json TEXT,
                failure_reason TEXT,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            );
            CREATE INDEX IF NOT EXISTS local_outbox_chat
                ON local_outbox(chat_id, created_at);
            CREATE TABLE IF NOT EXISTS local_sync_state (
                state_key TEXT PRIMARY KEY,
                value TEXT NOT NULL,
                updated_at REAL NOT NULL
            );
            CREATE TABLE IF NOT EXISTS local_metadata (
                meta_key TEXT PRIMARY KEY,
                value TEXT NOT NULL,
                updated_at REAL NOT NULL
            );
            PRAGMA user_version = 1;
            """)
    }

    private func write(_ body: (OpaquePointer) -> Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let database else { return false }
        guard executeUnlocked("BEGIN IMMEDIATE") else { return false }
        guard body(database), executeUnlocked("COMMIT") else {
            _ = executeUnlocked("ROLLBACK")
            return false
        }
        return true
    }

    private func read<T>(_ body: (OpaquePointer) -> T?) -> T? {
        lock.lock()
        defer { lock.unlock() }
        guard let database else { return nil }
        return body(database)
    }

    @discardableResult
    private func executeUnlocked(_ sql: String) -> Bool {
        guard let database else { return false }
        var error: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(database, sql, nil, nil, &error)
        if result != SQLITE_OK {
            if let error {
                NSLog("[LocalDB] %@", String(cString: error))
            }
            sqlite3_free(error)
            return false
        }
        return true
    }

    private func setMetadata(
        _ db: OpaquePointer,
        key: String,
        value: String,
        now: TimeInterval
    ) -> Bool {
        let sql = """
            INSERT INTO local_metadata (meta_key, value, updated_at)
            VALUES (?, ?, ?)
            ON CONFLICT(meta_key) DO UPDATE SET
                value = excluded.value,
                updated_at = excluded.updated_at
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { return false }
        defer { sqlite3_finalize(statement) }
        bind(key, to: statement, at: 1)
        bind(value, to: statement, at: 2)
        sqlite3_bind_double(statement, 3, now)
        return sqlite3_step(statement) == SQLITE_DONE
    }

    private func bind(_ value: String, to statement: OpaquePointer, at index: Int32) {
        value.withCString {
            sqlite3_bind_text(statement, index, $0, -1, localSQLiteTransient)
        }
    }

    private func bindOptional(
        _ value: String?,
        to statement: OpaquePointer,
        at index: Int32
    ) {
        if let value {
            bind(value, to: statement, at: index)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func bind(_ value: Data, to statement: OpaquePointer, at index: Int32) {
        value.withUnsafeBytes { bytes in
            sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(bytes.count),
                              localSQLiteTransient)
        }
    }

    private func text(_ statement: OpaquePointer, column: Int32) -> String {
        optionalText(statement, column: column) ?? ""
    }

    private func optionalText(_ statement: OpaquePointer, column: Int32) -> String? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL,
              let value = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: value)
    }

    private func blob(_ statement: OpaquePointer, column: Int32) -> Data? {
        let count = Int(sqlite3_column_bytes(statement, column))
        guard count > 0, let bytes = sqlite3_column_blob(statement, column) else { return nil }
        return Data(bytes: bytes, count: count)
    }

    private func encodeStringArray(_ values: [String]) -> String {
        guard let data = try? JSONEncoder().encode(values),
              let text = String(data: data, encoding: .utf8) else { return "[]" }
        return text
    }

    private func decodeStringArray(_ value: String) -> [String] {
        guard let data = value.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    private func lastErrorMessage() -> String {
        guard let database else { return "database unavailable" }
        return String(cString: sqlite3_errmsg(database))
    }
}

enum LocalPersistence {
    private static let signatureLock = NSLock()
    private static var chatSignatures: [String: Int] = [:]

    static func loadChat(_ chatId: String) -> [Message] {
        let db = LocalDatabase.shared
        let migrationKey = chatMigrationKey(chatId)
        var legacy: [Message] = []
        if db.chatNeedsLegacyMigration(migrationKey) {
            legacy = LocalStore.cachedLegacyChat(chatId)
            if !legacy.isEmpty {
                _ = saveChat(chatId, legacy)
            } else {
                _ = db.markChatMigrated(migrationKey)
            }
        }
        let stored = db.loadChat(chatId)
        return stored.isEmpty ? legacy : stored
    }

    @discardableResult
    static func saveChat(_ chatId: String, _ messages: [Message]) -> Bool {
        guard !chatId.isEmpty, !messages.isEmpty else { return false }
        let tail = Array(messages.suffix(5000))
        var hasher = Hasher()
        hasher.combine(tail.count)
        for message in tail {
            hasher.combine(message.id)
            hasher.combine(message.clientId)
            hasher.combine(message.seq)
            hasher.combine(message.body)
            hasher.combine(message.isRecalled)
        }
        let signature = hasher.finalize()
        signatureLock.lock()
        let unchanged = chatSignatures[chatId] == signature
        signatureLock.unlock()
        guard !unchanged else { return true }
        let saved = LocalDatabase.shared.saveChat(
            chatId,
            messages: tail,
            migrationKey: chatMigrationKey(chatId)
        )
        if saved {
            signatureLock.lock()
            chatSignatures[chatId] = signature
            signatureLock.unlock()
        }
        return saved
    }

    static func clearChat(_ chatId: String) {
        _ = LocalDatabase.shared.clearChat(chatId)
        signatureLock.lock()
        chatSignatures.removeValue(forKey: chatId)
        signatureLock.unlock()
    }

    static func loadOutbox(_ chatId: String) -> [PendingMsg] {
        let rows = LocalDatabase.shared.loadOutbox(chatId)
        if !rows.isEmpty { return rows }

        let legacyKey = "chris.outbox." + chatId
        let legacy = (UserDefaults.standard.array(forKey: legacyKey) as? [[String: Any]]) ?? []
        let migrated = legacy.compactMap { value -> PendingMsg? in
            guard let id = value["id"] as? String,
                  let kind = value["kind"] as? String,
                  let content = value["content"] as? String else { return nil }
            let at = (value["at"] as? TimeInterval)
                .map(Date.init(timeIntervalSince1970:)) ?? Date()
            let failure = value["failureReason"] as? String
            return PendingMsg(
                id: id,
                kind: kind,
                content: content,
                mentions: value["mentions"] as? [String] ?? [],
                quoteJSON: value["quote"] as? String,
                failed: !(failure ?? "").isEmpty,
                failureReason: failure,
                at: at
            )
        }
        guard !migrated.isEmpty else { return [] }
        if LocalDatabase.shared.saveOutbox(chatId, messages: migrated) {
            UserDefaults.standard.removeObject(forKey: legacyKey)
        }
        return migrated
    }

    static func saveOutbox(_ chatId: String, _ messages: [PendingMsg]) {
        _ = LocalDatabase.shared.saveOutbox(chatId, messages: messages)
    }

    static func syncValue(_ key: String) -> String? {
        if let value = LocalDatabase.shared.syncValue(key) {
            return value
        }
        guard let legacy = UserDefaults.standard.object(forKey: key) else { return nil }
        let value: String
        if let string = legacy as? String {
            value = string
        } else if let number = legacy as? NSNumber {
            value = number.stringValue
        } else {
            return nil
        }
        guard !value.isEmpty else {
            UserDefaults.standard.removeObject(forKey: key)
            return nil
        }
        if LocalDatabase.shared.setSyncValue(key, value: value) {
            UserDefaults.standard.removeObject(forKey: key)
        }
        return value
    }

    static func setSyncValue(_ value: String?, for key: String) {
        if LocalDatabase.shared.setSyncValue(key, value: value) {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private static func chatMigrationKey(_ chatId: String) -> String {
        "chat:" + API.shared.cacheNamespace + ":" + chatId
    }
}
