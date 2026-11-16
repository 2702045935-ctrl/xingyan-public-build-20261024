import Foundation

/// Local-only message fixture for ChatDetail stress runs. It never writes to
/// the server or the normal local cache.
enum MessageStressFixture {
    static let chatId = "stress-message-chat"

    static let count: Int = {
        guard let raw = ProcessInfo.processInfo.environment["XINGYAN_MESSAGE_STRESS"],
              let value = Int(raw) else { return 0 }
        return max(0, min(100_000, value))
    }()

    static let isActive = count > 0

    static func isStressChat(_ id: String) -> Bool {
        id == chatId
    }

    static let chat: Chat = {
        let stamp = "2026-11-16T00:00:00Z"
        let last = LastMessage(
            id: "stress-message-\(count)",
            senderId: "stress-peer",
            senderName: "压力测试用户",
            kind: "text",
            preview: "第 \(count) 条本地压力消息",
            createdAt: stamp,
            mentionMe: false
        )
        return Chat(
            id: chatId,
            type: "group",
            title: "消息压力测试 \(count)",
            avatar: "",
            unread: 0,
            pinned: true,
            botRank: 9,
            memberCount: 12,
            memberIds: ["stress-self", "stress-peer"],
            onlineMemberIds: ["stress-peer"],
            lastMessage: last,
            updatedAt: stamp,
            muted: false
        )
    }()

    static func messages(myId: String) -> [Message] {
        guard isActive else { return [] }
        let me = myId.isEmpty ? "stress-self" : myId
        let bucketStamps: [String] = (0...(max(1, count) / 1_000)).map { bucket in
            let base = Date(timeIntervalSince1970: 1_763_251_200)
            return ISO8601DateFormatter().string(
                from: base.addingTimeInterval(Double(bucket) * 3_600)
            )
        }
        return (1...count).map { seq in
            let mine = seq % 3 == 0
            let holder = mine ? me : "stress-peer"
            let stamp = bucketStamps[min(bucketStamps.count - 1, (seq - 1) / 1_000)]
            let mentions = seq % 127 == 0 ? [me] : nil
            let content = seq % 43 == 0
                ? "这是一条更长的压力消息 \(seq)，用于验证多行气泡、时间、头像、已读和长列表布局。"
                : "本地压力消息 \(seq)"
            return Message(
                id: "stress-message-\(seq)",
                clientId: "stress-client-\(seq)",
                chatId: chatId,
                seq: seq,
                senderId: holder,
                kind: "text",
                content: content,
                createdAt: stamp,
                recalled: false,
                quote: nil,
                burn: false,
                burnAt: nil,
                senderName: mine ? "我" : "压力测试用户",
                senderAvatar: nil,
                call: nil,
                mentions: mentions,
                imgW: nil,
                imgH: nil
            )
        }
    }
}
