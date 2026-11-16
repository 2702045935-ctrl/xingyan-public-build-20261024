import Foundation

/// Local-only message and group fixture for ChatDetail and ChatInfo stress
/// runs. It never writes to the backend or the normal local message cache.
enum MessageStressFixture {
    static let count = StressTestConfiguration.messageCount
    static let groupCount = StressTestConfiguration.messageGroupCount
    static let isActive = count > 0 && groupCount > 0
    static let autoOpen = StressTestConfiguration.autoOpenMessageChat

    private static let prefix = "stress-message-chat-"
    private static let stamp = "2026-11-16T00:00:00Z"
    private static let lock = NSRecursiveLock()
    private static var cachedUserID = ""
    private static var cachedMessages: [String: [Message]] = [:]

    static let members: [User] = (0..<StressTestConfiguration.memberCount).map { index in
        User(
            id: "stress-member-\(index)",
            nickname: "压力成员 \(index + 1)",
            avatar: ""
        )
    }

    static let chats: [Chat] = {
        guard isActive else { return [] }
        let memberIDs = members.map(\.id)
        return (0..<groupCount).map { group in
            let id = chatID(group)
            return Chat(
                id: id,
                type: "group",
                title: "消息压力 \(group + 1) · \(count) 条",
                avatar: "",
                unread: group == 0 ? 0 : group % 97,
                pinned: group == 0,
                botRank: 9,
                memberCount: memberIDs.count,
                memberIds: memberIDs,
                onlineMemberIds: Array(memberIDs.prefix(12)),
                lastMessage: LastMessage(
                    id: "\(id)-last",
                    senderId: "stress-peer",
                    senderName: "压力测试用户",
                    kind: "text",
                    preview: "第 \(group + 1) 组消息压力测试",
                    createdAt: stamp,
                    mentionMe: false
                ),
                updatedAt: stamp,
                muted: false
            )
        }
    }()

    static var firstChat: Chat? { chats.first }

    static func isStressChat(_ id: String) -> Bool {
        id.hasPrefix(prefix)
    }

    static func chatID(_ group: Int) -> String {
        prefix + String(group)
    }

    static func messagesByChat(myId: String) -> [String: [Message]] {
        guard isActive else { return [:] }
        let me = myId.isEmpty ? "stress-self" : myId
        lock.lock()
        defer { lock.unlock() }
        if cachedUserID == me, !cachedMessages.isEmpty {
            return cachedMessages
        }

        let dominantCount = groupCount > 1 ? count * 3 / 4 : count
        let remainingCount = count - dominantCount
        let otherGroups = max(0, groupCount - 1)
        let basePerGroup = otherGroups > 0 ? remainingCount / otherGroups : 0
        let remainder = otherGroups > 0 ? remainingCount % otherGroups : 0
        var output: [String: [Message]] = [:]
        output.reserveCapacity(groupCount)
        let buckets = (0...(max(1, count) / 1_000)).map { bucket -> String in
            let date = Date(timeIntervalSince1970: 1_763_251_200)
                .addingTimeInterval(Double(bucket) * 3_600)
            return ISO8601DateFormatter().string(from: date)
        }

        var ordinal = 0
        for group in 0..<groupCount {
            let groupSize: Int
            if group == 0 {
                groupSize = dominantCount
            } else {
                groupSize = basePerGroup + (group - 1 < remainder ? 1 : 0)
            }
            var rows: [Message] = []
            rows.reserveCapacity(groupSize)
            for seq in 1...max(1, groupSize) {
                ordinal += 1
                if seq > groupSize { break }
                let mine = ordinal % 3 == 0
                let sender = mine ? me : "stress-peer-\(ordinal % 12)"
                let mention = ordinal % 127 == 0 ? [me] : nil
                let timestamp = buckets[min(buckets.count - 1, (ordinal - 1) / 1_000)]
                let quoted = ordinal % 109 == 0 && seq > 1
                    ? QuoteRef(
                        id: "stress-message-\(group)-\(seq - 1)",
                        who: mine ? "对方" : "我",
                        text: "引用上一条压力消息",
                        kind: "text",
                        thumb: nil
                    )
                    : nil
                let recalled = ordinal % 211 == 0
                let kind: String
                let content: String
                if recalled {
                    kind = "text"
                    content = "这条消息已经被撤回"
                } else if ordinal % 173 == 0 {
                    kind = "file"
                    content = "{\"name\":\"压力资料-\(ordinal).pdf\",\"size\":1048576,\"url\":\"\"}"
                } else if ordinal % 151 == 0 {
                    kind = "transfer"
                    content = "{\"amount\":128.0,\"status\":\"done\",\"note\":\"压力测试\"}"
                } else if ordinal % 43 == 0 {
                    kind = "text"
                    content = "这是一条较长的消息 \(ordinal)。用于验证多行气泡、头像、时间、@、引用和长列表布局是否稳定，滚动中不应重排。"
                } else {
                    kind = "text"
                    content = "本地压力消息 \(ordinal)"
                }
                rows.append(Message(
                    id: "stress-message-\(group)-\(seq)",
                    clientId: "stress-client-\(group)-\(seq)",
                    chatId: chatID(group),
                    seq: seq,
                    senderId: sender,
                    kind: kind,
                    content: content,
                    createdAt: timestamp,
                    recalled: recalled,
                    quote: quoted,
                    burn: false,
                    burnAt: nil,
                    senderName: mine ? "我" : "压力测试用户 \(ordinal % 12 + 1)",
                    senderAvatar: nil,
                    call: nil,
                    mentions: mention,
                    imgW: nil,
                    imgH: nil
                ))
            }
            output[chatID(group)] = rows
        }
        cachedUserID = me
        cachedMessages = output
        return output
    }

    static func page(
        chatId: String,
        limit: Int,
        before: Int?,
        since: Int?,
        all: Bool
    ) -> (chat: Chat?, messages: [Message], hasMore: Bool) {
        guard isStressChat(chatId) else {
            return (nil, [], false)
        }
        lock.lock()
        let current = cachedMessages
        lock.unlock()
        let source = current.isEmpty
            ? messagesByChat(myId: "stress-self")
            : current
        let rows = source[chatId] ?? []
        let cap = max(1, min(all ? 20_000 : 500, limit))
        if let since {
            let candidates = rows.filter { ($0.seq ?? 0) > since }
            return (chats.first { $0.id == chatId }, Array(candidates.prefix(cap)), candidates.count > cap)
        }
        if let before {
            let candidates = rows.filter { ($0.seq ?? 0) < before }
            let page = Array(candidates.suffix(cap))
            return (chats.first { $0.id == chatId }, page, candidates.count - page.count > 0)
        }
        let page = Array(rows.suffix(cap))
        return (chats.first { $0.id == chatId }, page, rows.count > page.count)
    }
}
