import Foundation
import IMContracts

public struct MessageWindowPolicy: Sendable, Equatable {
    public var pageSize: Int
    public var runwayPages: Int
    public var maxMaterialized: Int

    public init(
        pageSize: Int = 120,
        runwayPages: Int = 3,
        maxMaterialized: Int = 50_000
    ) {
        self.pageSize = max(1, pageSize)
        self.runwayPages = max(1, runwayPages)
        self.maxMaterialized = max(self.pageSize, maxMaterialized)
    }

    public var runwayTarget: Int {
        pageSize * runwayPages
    }
}

public enum MessageWindowMutation: Sendable, Equatable {
    case noChange
    case inserted(count: Int, atStart: Bool)
    case replaced(count: Int)
}

public actor MessageWindow {
    public private(set) var policy: MessageWindowPolicy
    public private(set) var hasOlder: Bool
    public private(set) var hasNewer: Bool
    public private(set) var olderCursor: Int64?
    public private(set) var newerCursor: Int64?

    private var storage: [IMMessageEnvelope] = []

    public init(
        policy: MessageWindowPolicy = MessageWindowPolicy(),
        hasOlder: Bool = true,
        hasNewer: Bool = false
    ) {
        self.policy = policy
        self.hasOlder = hasOlder
        self.hasNewer = hasNewer
    }

    public func snapshot() -> [IMMessageEnvelope] {
        storage
    }

    public func replace(
        with messages: [IMMessageEnvelope],
        hasOlder: Bool,
        hasNewer: Bool
    ) {
        storage = Self.ordered(messages)
        self.hasOlder = hasOlder
        self.hasNewer = hasNewer
        refreshCursors()
    }

    @discardableResult
    public func merge(
        _ incoming: [IMMessageEnvelope],
        direction: IMHistoryDirection,
        reportedHasMore: Bool,
        nextCursor: Int64?
    ) -> MessageWindowMutation {
        let previousIDs = Set(storage.map(\.id))
        let previousCount = storage.count
        let merged = Self.ordered(storage + incoming)
        let freshCount = Set(merged.map(\.id)).subtracting(previousIDs).count

        if merged.count > policy.maxMaterialized {
            storage = direction == .older
                ? Array(merged.prefix(policy.maxMaterialized))
                : Array(merged.suffix(policy.maxMaterialized))
        } else {
            storage = merged
        }

        switch direction {
        case .older:
            hasOlder = reportedHasMore
            olderCursor = nextCursor
        case .newer:
            hasNewer = reportedHasMore
            newerCursor = nextCursor
        }
        refreshCursors()

        if freshCount > 0 {
            return .inserted(count: freshCount, atStart: direction == .older)
        }
        if storage.count != previousCount {
            return .replaced(count: storage.count)
        }
        return .noChange
    }

    public func appendRealtime(_ message: IMMessageEnvelope) {
        merge(
            [message],
            direction: .newer,
            reportedHasMore: hasNewer,
            nextCursor: newerCursor
        )
    }

    public func remove(_ ids: Set<IMMessageID>) {
        guard !ids.isEmpty else { return }
        storage.removeAll { ids.contains($0.id) }
        refreshCursors()
    }

    private func refreshCursors() {
        olderCursor = storage.compactMap(\.sequence).min()
        newerCursor = storage.compactMap(\.sequence).max()
    }

    private static func ordered(
        _ messages: [IMMessageEnvelope]
    ) -> [IMMessageEnvelope] {
        var byID: [IMMessageID: IMMessageEnvelope] = [:]
        for message in messages {
            byID[message.id] = message
        }
        return byID.values.sorted {
            let lhs = $0.sequence ?? Int64.min
            let rhs = $1.sequence ?? Int64.min
            if lhs != rhs { return lhs < rhs }
            if $0.createdAt != $1.createdAt {
                return $0.createdAt < $1.createdAt
            }
            return $0.id.rawValue < $1.id.rawValue
        }
    }
}
