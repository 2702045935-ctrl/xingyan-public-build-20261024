import Foundation
import MetricKit

/* MetricKit 只负责系统级性能数据：崩溃、卡死、CPU 异常、磁盘写入异常和能耗。
   原始 payload 保存在 Caches/XingyanMetrics，最多保留 40 份；不参与聊天、媒体或本地保存。 */
final class AppMetrics: NSObject, MXMetricManagerSubscriber {
    static let shared = AppMetrics()

    private let lock = NSLock()
    private var started = false

    private override init() { super.init() }

    func start() {
        lock.lock()
        defer { lock.unlock() }
        guard !started else { return }
        started = true
        MXMetricManager.shared.add(self)
        AppLog.info("MetricKit 已启用")
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        persist(kind: "metric", payloads.map { $0.jsonRepresentation() })
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        persist(kind: "diagnostic", payloads.map { $0.jsonRepresentation() })
    }

    private func metricsDir() -> URL? {
        guard let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        else { return nil }
        let dir = cache.appendingPathComponent("XingyanMetrics", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func persist(kind: String, _ payloads: [Data]) {
        guard !payloads.isEmpty, let dir = metricsDir() else { return }
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        for (index, data) in payloads.enumerated() {
            guard data.count <= 8 * 1024 * 1024 else { continue }
            let file = dir.appendingPathComponent("\(kind)-\(stamp)-\(index).json")
            try? data.write(to: file, options: [.atomic])
        }
        trim(dir)
        AppLog.info("MetricKit 收到 \(kind) \(payloads.count) 份")
    }

    private func trim(_ dir: URL) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let sorted = files.sorted {
            let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return a > b
        }
        for old in sorted.dropFirst(40) {
            try? FileManager.default.removeItem(at: old)
        }
    }
}
