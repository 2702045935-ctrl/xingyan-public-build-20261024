import SwiftUI

final class MsgFrameBox {
    var frames: [String: CGRect] = [:]
}

enum RichBodyCache {
    private static var store: [String: AttributedString] = [:]

    static func get(_ key: String) -> AttributedString? { store[key] }

    static func put(_ key: String, _ value: AttributedString) {

        if store.count > 12_000 { store.removeAll(keepingCapacity: true) }
        store[key] = value
    }
}

struct MsgFrameKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { a, _ in a }
    }
}
