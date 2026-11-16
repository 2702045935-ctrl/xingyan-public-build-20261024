import Foundation

/// Local-only conversation fixture used by the device stress harness.
/// It is enabled only through the launch environment and never touches server data.
enum ChatStressFixture {
    static let count = StressTestConfiguration.chatCount

    static let isActive = count > 0

    static let chats: [Chat] = {
        guard isActive else { return [] }
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
        let base = Date()
        let iso = ISO8601DateFormatter()

        return (0..<count).map { index in
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
    }()
}
