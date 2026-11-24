import Foundation

public struct IMChatID: Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.init(value)
    }
}

public struct IMMessageID: Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.init(value)
    }
}

public struct IMUserID: Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.init(value)
    }
}

public enum IMMessageKind: String, Codable, Sendable {
    case text
    case image
    case images
    case video
    case audio
    case file
    case location
    case card
    case system
    case unknown
}

public enum IMMessageDeliveryState: String, Codable, Sendable {
    case pending
    case sent
    case delivered
    case read
    case failed
}

public struct IMMessageEnvelope: Codable, Sendable, Identifiable, Equatable {
    public let id: IMMessageID
    public let clientID: String?
    public let chatID: IMChatID
    public let senderID: IMUserID
    public let kind: IMMessageKind
    public let body: String
    public let sequence: Int64?
    public let createdAt: Date
    public let mentions: [IMUserID]

    public init(
        id: IMMessageID,
        clientID: String? = nil,
        chatID: IMChatID,
        senderID: IMUserID,
        kind: IMMessageKind,
        body: String,
        sequence: Int64? = nil,
        createdAt: Date,
        mentions: [IMUserID] = []
    ) {
        self.id = id
        self.clientID = clientID
        self.chatID = chatID
        self.senderID = senderID
        self.kind = kind
        self.body = body
        self.sequence = sequence
        self.createdAt = createdAt
        self.mentions = mentions
    }
}

public enum IMHistoryDirection: String, Codable, Sendable {
    case older
    case newer
}

public struct IMHistoryPageRequest: Codable, Sendable, Equatable {
    public let chatID: IMChatID
    public let direction: IMHistoryDirection
    public let cursor: Int64?
    public let limit: Int

    public init(
        chatID: IMChatID,
        direction: IMHistoryDirection,
        cursor: Int64?,
        limit: Int
    ) {
        self.chatID = chatID
        self.direction = direction
        self.cursor = cursor
        self.limit = max(1, limit)
    }
}

public struct IMHistoryPage: Codable, Sendable, Equatable {
    public let messages: [IMMessageEnvelope]
    public let hasMore: Bool
    public let nextCursor: Int64?

    public init(
        messages: [IMMessageEnvelope],
        hasMore: Bool,
        nextCursor: Int64?
    ) {
        self.messages = messages
        self.hasMore = hasMore
        self.nextCursor = nextCursor
    }
}

public enum IMConnectionState: String, Codable, Sendable {
    case disconnected
    case connecting
    case connected
    case reconnecting
}

public enum IMRealtimeEvent: Sendable, Equatable {
    case connectionChanged(IMConnectionState)
    case messageCreated(IMMessageEnvelope)
    case messageUpdated(IMMessageEnvelope)
    case messageDeleted(chatID: IMChatID, messageID: IMMessageID)
    case deliveryChanged(
        chatID: IMChatID,
        messageID: IMMessageID,
        state: IMMessageDeliveryState
    )
    case typing(chatID: IMChatID, userID: IMUserID, active: Bool)
}

public protocol IMMessageRepository: Sendable {
    func historyPage(_ request: IMHistoryPageRequest) async throws -> IMHistoryPage
    func send(_ message: IMMessageEnvelope) async throws -> IMMessageEnvelope
}

public protocol IMRealtimeEventSource: Sendable {
    var events: AsyncStream<IMRealtimeEvent> { get }
    func connect() async
    func disconnect() async
}

public protocol IMUploadProgressReporting: Sendable {
    func upload(
        source: URL,
        preferredName: String,
        onProgress: @Sendable (Double) async -> Void
    ) async throws -> URL
}

public protocol IMThemeProviding: Sendable {
    var brandAccent: String { get }
    var preferredColorScheme: String { get }
}
