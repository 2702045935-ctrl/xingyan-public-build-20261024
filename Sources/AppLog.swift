import Foundation
import os

enum AppLog {
    private static let appLogger = Logger(subsystem: "com.chris.chatnative", category: "app")
    private static let netLogger = Logger(subsystem: "com.chris.chatnative", category: "net")
    private static let crashLogger = Logger(subsystem: "com.chris.chatnative", category: "crash")

    private static let lock = NSLock()
    private static var lastSent: [String: Date] = [:]

    static func info(_ text: String, net: Bool = false) {
        if net { netLogger.info("\(text, privacy: .public)") }
        else { appLogger.info("\(text, privacy: .public)") }
        DiagLog.shared.note(text)
    }

    static func error(_ kind: String, _ text: String) {
        crashLogger.error("[\(kind, privacy: .public)] \(text, privacy: .public)")
        DiagLog.shared.note(kind + "：" + text)
        lock.lock()
        let now = Date()
        let prev = lastSent[kind]
        let allow = (prev == nil) || now.timeIntervalSince(prev!) > 60
        if allow { lastSent[kind] = now }
        lock.unlock()
        guard allow else { return }
        CrashCatcher.note(kind, text)
    }

    static func crash(_ text: String) {
        crashLogger.fault("\(text, privacy: .public)")
    }
}
