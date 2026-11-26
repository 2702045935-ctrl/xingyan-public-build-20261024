import SwiftUI

enum RichBodyCache {
    private static var store: [String: AttributedString] = [:]

    static func get(_ key: String) -> AttributedString? { store[key] }

    static func put(_ key: String, _ value: AttributedString) {

        if store.count > 12_000 { store.removeAll(keepingCapacity: true) }
        store[key] = value
    }
}
