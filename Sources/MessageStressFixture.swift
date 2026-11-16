import Foundation

/// Local-only message and group fixture for ChatDetail and ChatInfo stress
/// runs. It never writes to the backend or the normal local message cache.
enum MessageStressFixture {
    static let count = StressTestConfiguration.messageCount
    static let groupCount = StressTestConfiguration.messageGroupCount
    static let isActive = count > 0 && groupCount > 0
    static let autoOpen = StressTestConfiguration.autoOpenMessageChat

    private static let prefix = "stress-message-chat-"
    private static let lock = NSRecursiveLock()
    private static var cachedUserID = ""

    private static let timestamps: [String] = {
        let formatter = ISO8601DateFormatter()
        let base = Date(timeIntervalSince1970: 1_763_251_200)
        return (0...(max(1, count) / 1_000)).map {
            formatter.string(from: base.addingTimeInterval(Double($0) * 3_600))
        }
    }()

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

    private static func rememberUser(_ myId: String?) -> String {
        let clean = (myId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        lock.lock()
        defer { lock.unlock() }
        if !clean.isEmpty { cachedUserID = clean }
        return cachedUserID.isEmpty ? "stress-self" : cachedUserID
    }

    private static func groupSize(_ group: Int) -> Int {
        guard group >= 0, group < groupCount else { return 0 }
        let dominantCount = groupCount > 1 ? count * 3 / 4 : count
        let remainingCount = count - dominantCount
        let otherGroups = max(0, groupCount - 1)
        let basePerGroup = otherGroups > 0 ? remainingCount / otherGroups : 0
        let remainder = otherGroups > 0 ? remainingCount % otherGroups : 0
        if group == 0 { return dominantCount }
        return basePerGroup + (group - 1 < remainder ? 1 : 0)
    }

    private static func ordinal(group: Int, seq: Int) -> Int {
        guard group > 0 else { return seq }
        let dominantCount = groupCount > 1 ? count * 3 / 4 : count
        let remainingCount = count - dominantCount
        let otherGroups = max(0, groupCount - 1)
        let basePerGroup = otherGroups > 0 ? remainingCount / otherGroups : 0
        let remainder = otherGroups > 0 ? remainingCount % otherGroups : 0
        let priorRemainders = min(max(0, group - 1), remainder)
        return dominantCount + (group - 1) * basePerGroup + priorRemainders + seq
    }

    private static func message(group: Int, seq: Int, myId: String) -> Message {
        let ordinal = ordinal(group: group, seq: seq)
        let mine = ordinal % 3 == 0
        let sender = mine ? myId : "stress-peer-\(ordinal % 12)"
        let mention = ordinal % 127 == 0 ? [myId] : nil
        let timestamp = timestamps[min(timestamps.count - 1, (ordinal - 1) / 1_000)]
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
        return Message(
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
        )
    }

    static func page(
        chatId: String,
        limit: Int,
        before: Int?,
        since: Int?,
        all: Bool,
        myId: String? = nil
    ) -> (chat: Chat?, messages: [Message], hasMore: Bool) {
        guard isStressChat(chatId) else {
            return (nil, [], false)
        }
        let group = Int(chatId.dropFirst(prefix.count)) ?? -1
        let size = groupSize(group)
        guard size > 0 else { return (nil, [], false) }
        let me = rememberUser(myId)
        let cap = max(1, min(all ? 20_000 : 500, limit))
        let start: Int
        let end: Int
        let hasMore: Bool
        if let since {
            start = max(1, since + 1)
            end = min(size, start + cap - 1)
            hasMore = end < size
        } else {
            let upper = min(size, max(0, (before ?? (size + 1)) - 1))
            end = upper
            start = max(1, end - cap + 1)
            hasMore = start > 1
        }
        guard start <= end else {
            return (chats.first { $0.id == chatId }, [], false)
        }
        let rows = (start...end).map { message(group: group, seq: $0, myId: me) }
        return (chats.first { $0.id == chatId }, rows, hasMore)
    }
}
