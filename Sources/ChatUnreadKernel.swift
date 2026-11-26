import Foundation

/// The single native source of truth for chat badges and incoming transitions.
///
/// Realtime events, reconnect reconciliation, list refreshes and local reads all
/// pass through this kernel. Keeping the policy here prevents each transport path
/// from growing its own unread and notification rules.
enum ChatUnreadKernel {
    static let foregroundRecoveryDelay: UInt64 = 3_000_000_000
    static let backgroundRecoveryDelay: UInt64 = 15_000_000_000

    static func iconValue(authoritativeTotal: Int?,
                          locallyHiddenUnread: Int,
                          chats: [Chat]) -> Int {
        if let authoritativeTotal {
            return clamp(authoritativeTotal - max(0, locallyHiddenUnread))
        }
        let fallback = chats.reduce(0) { total, chat in
            guard chat.muted != true, chat.botRank != 0 else { return total }
            return total + max(0, chat.unreadCount)
        }
        return clamp(fallback)
    }

    static func realtimeUnread(current: Int,
                               incoming: Int,
                               previousMessageId: String,
                               newMessageId: String,
                               senderIsMe: Bool,
                               openChatId: String?,
                               chatId: String) -> Int {
        guard openChatId != chatId else { return 0 }
        let isNewIncoming = !senderIsMe
            && !newMessageId.isEmpty
            && newMessageId != previousMessageId
        if isNewIncoming, incoming <= current {
            return clamp(current + 1)
        }
        return clamp(max(current, incoming))
    }

    static func unreadAfterReceivingMessage(current: Int,
                                            isNewMessage: Bool,
                                            senderIsMe: Bool,
                                            openChatId: String?,
                                            chatId: String) -> Int {
        guard openChatId != chatId else { return 0 }
        guard isNewMessage, !senderIsMe else { return max(0, current) }
        return clamp(current + 1)
    }

    static func shouldNotify(previous: Chat?,
                             current: Chat?,
                             openChatId: String?,
                             allowNewChat: Bool) -> Bool {
        guard let current,
              current.id != openChatId,
              current.muted != true,
              current.unreadCount > 0 else { return false }
        let newMessageId = current.lastMessage?.id ?? ""
        guard !newMessageId.isEmpty else { return false }
        guard let previous else { return allowNewChat }
        let previousMessageId = previous.lastMessage?.id ?? ""
        if current.unreadCount > previous.unreadCount { return true }
        guard newMessageId != previousMessageId else { return false }
        return (current.updatedAt ?? "") > (previous.updatedAt ?? "")
    }

    private static func clamp(_ value: Int) -> Int {
        min(999, max(0, value))
    }
}
