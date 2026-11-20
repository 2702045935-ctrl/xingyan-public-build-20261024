import Foundation

/// Shared switchboard for opt-in device stress fixtures. These values only
/// change synthetic, local data and never alter the backend or normal caches.
enum StressTestConfiguration {
    private static let environment = ProcessInfo.processInfo.environment
    private static let profile = (environment["XINGYAN_STRESS_PROFILE"] ?? "").lowercased()
    private static let eagerMessages100K = profile == "messages-100000-eager"
    private static let largeGroupPressure = profile == "group-300000-members-10000"
    private static let hardCap = 300_000

    private static func value(_ key: String) -> Int? {
        guard let raw = environment[key], let number = Int(raw) else { return nil }
        return max(0, min(hardCap, number))
    }

    private static func profileValue(_ prefix: String) -> Int? {
        guard profile.hasPrefix(prefix) else { return nil }
        let suffix = profile.dropFirst(prefix.count)
        guard let value = Int(suffix) else { return nil }
        return max(0, min(hardCap, value))
    }

    static let chatCount: Int = {
        value("XINGYAN_CHAT_STRESS")
            ?? profileValue("chats-")
            ?? (profile == "full-100000" ? 100_000 : 0)
    }()

    static let messageCount: Int = {
        value("XINGYAN_MESSAGE_STRESS")
            ?? profileValue("messages-")
            ?? profileValue("chat-")
            ?? (largeGroupPressure ? 300_000
                : (eagerMessages100K || profile == "full-100000" ? 100_000 : 0))
    }()

    static let momentCount: Int = {
        value("XINGYAN_MOMENT_STRESS")
            ?? profileValue("moments-")
            ?? (profile == "full-100000" ? 100_000 : 0)
    }()

    static let messageGroupCount: Int = {
        let raw = environment["XINGYAN_STRESS_GROUPS"].flatMap(Int.init) ?? 1
        return messageCount > 0 ? max(1, min(500, raw)) : 0
    }()

    static let memberCount: Int = {
        if largeGroupPressure { return 10_000 }
        let raw = environment["XINGYAN_STRESS_MEMBERS"].flatMap(Int.init) ?? 8
        return max(1, min(10_000, raw))
    }()

    static let autoOpenMessageChat: Bool = {
        if eagerMessages100K { return false }
        if let raw = environment["XINGYAN_STRESS_AUTO_OPEN"] {
            return ["1", "true", "yes", "on"].contains(raw.lowercased())
        }
        return messageCount > 0
    }()

    /// Opt-in destructive performance test: materialise the complete message
    /// fixture in memory instead of generating only the visible history window.
    static let eagerMessageMaterialization: Bool = {
        if eagerMessages100K { return true }
        let raw = environment["XINGYAN_STRESS_EAGER"] ?? ""
        return ["1", "true", "yes", "on"].contains(raw.lowercased())
    }()
}
