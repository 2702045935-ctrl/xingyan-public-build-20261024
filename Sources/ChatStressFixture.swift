import Foundation

/// Local-only conversation fixture used by the device stress harness.
/// It is enabled only through the launch environment and never touches server data.
enum ChatStressFixture {
    static let count = StressTestConfiguration.chatCount

    static let isActive = count > 0

    static let initialWindow = min(count, 160)
    static let pageSize = 120
    static let maxActiveWindow = 2_400
    private static let lock = NSLock()
    private static var cache: [Chat] = []

    /// The stress source is index based. Building all 100,000 value rows up
    /// front makes the launch measurement test fixture generation rather than
    /// the list itself, so callers materialize only their active window.
    static func chats(prefix: Int) -> [Chat] {
        guard isActive else { return [] }
        let upper = max(0, min(count, prefix))
        return chats(range: 0..<upper)
    }

    static func chats(range: Range<Int>) -> [Chat] {
        guard isActive, !range.isEmpty else { return [] }
        let lower = max(0, min(count, range.lowerBound))
        let upper = max(lower, min(count, range.upperBound))
        guard lower < upper else { return [] }
        lock.lock()
        defer { lock.unlock() }
        while cache.count < upper {
            cache.append(chat(at: cache.count))
        }
        return Array(cache[lower..<upper])
    }

    private static let base = Date()

    private static func chat(at index: Int) -> Chat {
        let previewKinds = ["text", "image", "file", "transfer", "call", "feed", "audio"]
        let previews = [
            "这是用于验证 4000 条会话滚动稳定性的测试消息",
            "[图片]",
            "[文件] 项目资料.pdf",
            "[转账] ¥128.00",
            "[语音通话]",
            "星轨动态更新",
            "[语音]"
        ]
        let iso = ISO8601DateFormatter()

        let stamp = iso.string(from: base.addingTimeInterval(-Double(index) * 60))
        let kind = previewKinds[index % previewKinds.count]
        let preview = previews[index % previews.count]
        let last = LastMessage(
            id: "stress-message-\(index)",
            senderId: "stress-peer-\(index)",
            senderName: "星友 \(index + 1)",
            kind: kind,
            preview: preview,
            createdAt: stamp,
            mentionMe: index % 53 == 0
        )
        let isGroup = index % 3 == 0
        let memberCount = isGroup ? 9 + (index % 120) : 2
        let memberIds = (0..<min(memberCount, 8)).map {
            "stress-member-\(index)-\($0)"
        }
        return Chat(
            id: "stress-chat-\(index)",
            type: isGroup ? "group" : "direct",
            title: String(format: "压力会话 %04d", index + 1),
            avatar: "",
            unread: index % 11 == 0 ? (index % 97) + 1 : 0,
            pinned: false,
            botRank: 9,
            memberCount: memberCount,
            memberIds: memberIds,
            onlineMemberIds: Array(memberIds.prefix(isGroup ? 4 : 1)),
            lastMessage: last,
            updatedAt: stamp,
            muted: index % 17 == 0
        )
    }
}
