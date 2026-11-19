import Foundation

enum InteractionMotion {
    static let quickResponse = 0.12
    static let pagePush = 0.32
    static let pagePop = 0.28
    static let interruptionSpring = (response: 0.28, damping: 0.90)
}

/// Small, dependency-free timing layer shared by page handoffs. Navigation
/// remains native; this records the source tap and destination first appearance
/// so regressions can be measured instead of guessed.
@MainActor
final class InteractionKernel {
    static let shared = InteractionKernel()

    private var pendingStart: [String: Date] = [:]
    private(set) var lastChatOpenMilliseconds: Double?

    func begin(page: String, id: String) {
        pendingStart[page + ":" + id] = Date()
    }

    @discardableResult
    func complete(page: String, id: String) -> Double? {
        let key = page + ":" + id
        guard let start = pendingStart.removeValue(forKey: key) else { return nil }
        let elapsed = Date().timeIntervalSince(start) * 1_000
        if page == "chat" {
            lastChatOpenMilliseconds = elapsed
        }
        return elapsed
    }
}
