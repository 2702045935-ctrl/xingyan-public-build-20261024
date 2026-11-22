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
    private static let testImage =
        "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9Zl1sAAAAASUVORK5CYII="
    private static let testDocument =
        "data:text/plain;base64," + Data(
            "星言文件卡片压力测试。\n聊天文件可以正常打开、预览和分享。".utf8
        ).base64EncodedString()

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
        var mine = ordinal % 100 < 22
        var sender = mine ? myId : "stress-peer-\(peerIndex(ordinal))"
        let timestamp = timestamps[min(timestamps.count - 1, (ordinal - 1) / 1_000)]
        let quoted = ordinal % 397 == 0 && seq > 1
            ? QuoteRef(
                id: "stress-message-\(group)-\(seq - 1)",
                who: mine ? "对方" : "我",
                text: "引用上一条压力消息",
                kind: "text",
                thumb: nil
            )
            : nil
        let recalled = ordinal % 179 == 0
        var kind = "text"
        var content = ""
        let bucket = ordinal % 10_000
        switch bucket {
        case 8768..<9348:
            kind = "image"
            content = testImage
        case 9348..<9536:
            kind = "pat"
            content = "{\"from\":\"\(sender)\",\"to\":\"\(myId)\",\"fn\":\"家人\",\"tn\":\"我\"}"
        case 9536..<9690:
            kind = "system"
            content = ordinal % 2 == 0 ? "你已加入群聊" : "一条群系统提示"
        case 9690..<9786:
            kind = "audio"
            content = "{\"url\":\"/uploads/stress-audio-\(ordinal).m4a\",\"seconds\":\(4 + ordinal % 46),\"bytes\":\(24_000 + ordinal % 80_000)}"
        case 9786..<9835:
            kind = "location"
            content = "{\"lat\":30.22537,\"lng\":120.22706,\"name\":\"滨盛路辅路\",\"addr\":\"杭州市 滨江区 滨盛路辅路\"}"
        case 9835..<9871:
            kind = "video"
            content = "{\"seconds\":\(8 + ordinal % 45),\"w\":720,\"h\":1280,\"cover\":\"\(testImage)\",\"url\":\"/uploads/stress-video-\(ordinal).mp4\"}"
        case 9871..<9904:
            kind = "redpacket"
            content = "{\"id\":\"stress-rp-\(ordinal)\",\"total\":\(ordinal % 100 + 1),\"count\":1,\"claimedCount\":1,\"claimedIds\":[\"\(myId)\"],\"type\":\"lucky\",\"note\":\"恭喜发财，大吉大利\",\"status\":\"done\",\"expired\":false,\"coverColor\":\"#8E1412\",\"fromId\":\"\(sender)\",\"fromName\":\"家人\"}"
        case 9904..<9936:
            kind = "images"
            content = "{\"paths\":[\"\(testImage)\",\"\(testImage)\",\"\(testImage)\"]}"
        case 9936..<9953:
            kind = "file"
            content = "{\"name\":\"家庭资料-\(ordinal).txt\",\"bytes\":\(testDocument.utf8.count),\"url\":\"\(testDocument)\"}"
        case 9953..<9968:
            kind = "livephoto"
            content = "{\"image\":\"\(testImage)\",\"video\":\"/uploads/stress-live-\(ordinal).mp4\"}"
        case 9968..<9976:
            kind = "miniapp"
            content = "{\"name\":\"斗地主\",\"icon\":\"🃏\",\"action\":\"立即玩\",\"url\":\"/games/05-doudizhu/index.html\",\"id\":\"g05\",\"desc\":\"和朋友来一局\",\"cover\":\"\(testImage)\",\"kind\":\"game\"}"
        case 9976..<9984:
            kind = "card"
            content = "{\"username\":\"family\(ordinal % 8 + 1)\",\"name\":\"家人名片\",\"userId\":\"stress-peer-\(peerIndex(ordinal))\",\"avatar\":\"\(testImage)\"}"
        case 9984..<9990:
            kind = "gift"
            content = "{\"id\":\"g03\",\"name\":\"花束\",\"icon\":\"💐\",\"price\":5}"
        case 9990..<9993:
            kind = "transfer"
            content = "{\"id\":\"stress-transfer-\(ordinal)\",\"amount\":\(ordinal % 200 + 1),\"note\":\"家里用\",\"status\":\"done\",\"method\":\"balance\",\"fromId\":\"\(sender)\",\"toId\":\"\(myId)\"}"
        case 9993..<9996:
            kind = "music"
            content = "{\"title\":\"家人分享的音乐\",\"url\":\"/uploads/stress-music-\(ordinal).mp3\"}"
        case 9996..<9998:
            kind = "announce"
            content = "📢【家人群公告】\n各位家人好，群内文明聊天，不吵架、不转发不实信息，不随意拉外人进群。重要事情群内通知，愿一家人平安顺遂。"
        case 9998..<10000:
            kind = "mall"
            content = "{\"id\":\"m03\",\"shop\":\"家庭好物\",\"em\":\"☕\",\"price\":13.03,\"orig\":39.9,\"img\":\"\(testImage)\",\"title\":\"咖啡杯316不锈钢保温杯\"}"
        default:
            if ordinal % 73 == 0 {
                content = "这是一条较长的家庭消息 \(ordinal)。今天大家都有空的话，晚上一起吃饭，老人家最近身体还可以，孩子这周学校有活动，照片和注意事项我整理在下面，大家看到后回复一下。"
            } else if ordinal % 7 == 0 {
                content = "好的，知道了"
            } else if ordinal % 5 == 0 {
                content = "哈哈哈"
            } else {
                content = "家里消息 \(ordinal)"
            }
        }
        if kind == "system" {
            mine = false
            sender = "system"
        }
        let mention = kind == "text" && ordinal % 47 == 0 ? [myId] : nil
        if mention != nil {
            content = "@我 " + content
        }
        if recalled {
            content = "这条消息已经被撤回"
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
            senderName: mine ? "我" : (kind == "system" ? "系统" : "压力成员 \(peerIndex(ordinal) + 1)"),
            senderAvatar: nil,
            call: nil,
            mentions: mention,
            imgW: nil,
            imgH: nil
        )
    }

    private static func peerIndex(_ ordinal: Int) -> Int {
        let bucket = (ordinal * 37) % 83
        if bucket < 25 { return 0 }
        if bucket < 47 { return 1 }
        if bucket < 65 { return 2 }
        if bucket < 74 { return 3 }
        if bucket < 79 { return 4 }
        if bucket < 81 { return 5 }
        return bucket < 82 ? 6 : 7
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
        let cap = max(1, min(
            StressTestConfiguration.eagerMessageMaterialization && all
                ? size
                : (all ? 20_000 : 500),
            limit
        ))
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
