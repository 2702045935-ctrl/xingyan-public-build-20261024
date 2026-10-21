import SwiftUI
import Foundation

private func chrisExceptionHandler(_ ex: NSException) {
    CrashCatcher.report("NSException", "\(ex.name.rawValue): \(ex.reason ?? "")")
}
private func chrisSignalHandler(_ s: Int32) {
    CrashCatcher.report("Signal", "signal \(s)\n" + Thread.callStackSymbols.joined(separator: "\n"))
    signal(s, SIG_DFL)
}

enum CrashCatcher {
    private static var installed = false

    private static var crashFile: URL? {
        guard let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        return dir.appendingPathComponent("chris-last-crash.txt")
    }
    private static func saveCrashFile(_ text: String) {
        guard let f = crashFile else { return }
        try? Data(text.prefix(20000).utf8).write(to: f, options: [.atomic])
    }
    private static func loadCrashFile() -> String {
        guard let f = crashFile, let d = try? Data(contentsOf: f) else { return "" }
        return String(data: d, encoding: .utf8) ?? ""
    }
    private static func clearCrashFile() { if let f = crashFile { try? FileManager.default.removeItem(at: f) } }

    static func install() {
        guard !installed else { return }
        installed = true

        NSSetUncaughtExceptionHandler(chrisExceptionHandler)
        for sig in [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGTRAP] {
            signal(sig, chrisSignalHandler)
        }

        uploadPending()

        launchBeacon()
    }

    private static func launchBeacon() {
        let payload: [String: Any] = [
            "kind": "launch",
            "text": AppInfo.build,
            "app": String(AppInfo.build.prefix(28))
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let url = URL(string: API.shared.base + "/api/clientlog") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 5
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = data

        API.shared.session.dataTask(with: req).resume()
    }

    static func uploadPending() {

        let fromFile = loadCrashFile()
        let raw = fromFile.isEmpty ? (UserDefaults.standard.string(forKey: "chris.lastCrash") ?? "") : fromFile
        let at = UserDefaults.standard.string(forKey: "chris.lastCrashAt") ?? ""
        guard !raw.isEmpty else { return }
        if (UserDefaults.standard.string(forKey: "chris.lastCrashSent") ?? "") == at { return }
        let parts = raw.components(separatedBy: "\n\n")
        let head = parts.first ?? raw
        let stack = parts.count > 1 ? parts[1] : ""
        let headLines = head.components(separatedBy: "\n")
        let kind = headLines.first ?? "Crash"
        let text = headLines.dropFirst().joined(separator: "\n")
        var payload: [String: Any] = [
            "kind": "补报/" + kind,
            "text": String(text.prefix(3000)),
            "stack": String(stack.prefix(6000)),
            "app": AppInfo.build.prefix(28).description,
            "at": at.isEmpty ? ISO8601DateFormatter().string(from: Date()) : at,
            "late": true
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload),
           let url = URL(string: API.shared.base + "/api/clientlog") {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.timeoutInterval = 6
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = data
            API.shared.session.dataTask(with: req) { _, resp, _ in
                if let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                    UserDefaults.standard.set(at, forKey: "chris.lastCrashSent")
                    clearCrashFile()
                }
            }.resume()
        }
    }

    static func report(_ kind: String, _ text: String) {
        note(kind, text, keepLocal: true)
    }

    static func savedCrash() -> String { loadCrashFile() }

    static func markStep(_ kind: String, _ text: String) {
        let stack = Thread.callStackSymbols.joined(separator: "\n")
        let raw = "\(kind)\n\(text)\n\n\(stack)"
        UserDefaults.standard.set(raw, forKey: "chris.lastCrash")
        UserDefaults.standard.set(ISO8601DateFormatter().string(from: Date()), forKey: "chris.lastCrashAt")
        saveCrashFile(raw)
    }

    static func clearStep() {
        UserDefaults.standard.removeObject(forKey: "chris.lastCrash")
        UserDefaults.standard.removeObject(forKey: "chris.lastCrashAt")
        clearCrashFile()
    }

    static func note(_ kind: String, _ text: String, keepLocal: Bool = false) {
        let stack = Thread.callStackSymbols.joined(separator: "\n")
        if keepLocal {

            UserDefaults.standard.set("\(kind)\n\(text)\n\n\(stack)".prefix(6000).description,
                                      forKey: "chris.lastCrash")
            UserDefaults.standard.set(ISO8601DateFormatter().string(from: Date()), forKey: "chris.lastCrashAt")

            saveCrashFile("\(kind)\n\(text)\n\n\(stack)")
        }
        let payload: [String: Any] = [
            "kind": kind,
            "text": String(text.prefix(4000)),
            "stack": keepLocal ? String(stack.prefix(6000)) : "",
            "lang": Lang.code,
            "app": AppInfo.build.prefix(28).description,
            "at": ISO8601DateFormatter().string(from: Date())
        ]
        guard let url = URL(string: API.shared.base + "/api/clientlog"),
              let body = try? JSONSerialization.data(withJSONObject: payload) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 3
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        if keepLocal {

            let sem = DispatchSemaphore(value: 0)
            API.shared.session.dataTask(with: req) { _, _, _ in sem.signal() }.resume()
            _ = sem.wait(timeout: .now() + 3)
        } else {

            API.shared.session.dataTask(with: req).resume()
        }
    }
}
