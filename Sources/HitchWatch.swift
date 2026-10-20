import Foundation

final class HitchWatch {
    static let shared = HitchWatch()

    private var page = ""
    private var timer: Timer?
    private var interval: TimeInterval = 0.5
    private var last = Date()
    private var count = 0
    private var worst: TimeInterval = 0
    private var reportedAt = Date.distantPast

    private init() { }

    func start(_ p: String) {
        page = p
        guard timer == nil else { return }
        last = Date()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        let now = Date()
        let gap = now.timeIntervalSince(last) - interval
        last = now

        if gap > 0.15 && gap < 3.0 {
            count += 1
            worst = max(worst, gap)
        } else if gap >= 3.0 {
            count = 0
            worst = 0
            return
        }

        let shouldReport = (count >= 3 || worst > 0.5) && now.timeIntervalSince(reportedAt) > 30
        guard shouldReport else { return }
        let msg = "卡顿 \(page)：\(count) 次，最长 \(Int(worst * 1000))ms"
        count = 0
        worst = 0
        reportedAt = now
        Task { await API.shared.callDiag(msg) }
    }
}
