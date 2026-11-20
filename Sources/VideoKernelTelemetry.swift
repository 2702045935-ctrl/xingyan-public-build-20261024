import Foundation

struct VideoKernelFeedbackEvent: Encodable {
    var eventId: String
    var itemId: String
    var type: String
    var at: String
    var watchMs: Int?
    var durationMs: Int?
    var progress: Double?
    var completed: Bool?
    var source: String?

    var dictionary: [String: Any] {
        var out: [String: Any] = [
            "eventId": eventId,
            "itemId": itemId,
            "type": type,
            "at": at
        ]
        if let watchMs { out["watchMs"] = watchMs }
        if let durationMs { out["durationMs"] = durationMs }
        if let progress { out["progress"] = progress }
        if let completed { out["completed"] = completed }
        if let source { out["source"] = source }
        return out
    }
}

@MainActor
final class VideoKernelTelemetry {
    static let shared = VideoKernelTelemetry()

    private let sessionId = UUID().uuidString
    private let dateFormatter = ISO8601DateFormatter()
    private var currentItemId = ""
    private var currentStartedAt: TimeInterval = 0
    private var currentProgress = 0.0
    private var currentDurationMs = 0
    private var currentCompleted = false
    private var pending: [VideoKernelFeedbackEvent] = []
    private var flushTask: Task<Void, Never>?
    private var sending = false

    private init() {}

    func begin(_ itemId: String) {
        guard !itemId.isEmpty else { return }
        if currentItemId == itemId { return }
        finishCurrent()
        currentItemId = itemId
        currentStartedAt = Date().timeIntervalSince1970
        currentProgress = 0
        currentDurationMs = 0
        currentCompleted = false
        enqueue(itemId, "impression")
        enqueue(itemId, "play")
        scheduleFlush()
    }

    func update(_ itemId: String, progress: Double, duration: Double) {
        guard itemId == currentItemId else { return }
        if progress.isFinite {
            currentProgress = max(currentProgress, min(1, max(0, progress)))
        }
        if duration.isFinite, duration > 0 {
            currentDurationMs = max(currentDurationMs, Int(duration * 1000))
        }
    }

    func complete(_ itemId: String) {
        guard itemId == currentItemId, !currentCompleted else { return }
        currentCompleted = true
        currentProgress = 1
        enqueue(itemId, "complete", progress: 1, completed: true)
        scheduleFlush()
    }

    func finish(_ itemId: String) {
        guard itemId == currentItemId else { return }
        finishCurrent()
    }

    func event(_ type: String, itemId: String) {
        guard !itemId.isEmpty else { return }
        enqueue(itemId, type)
        scheduleFlush()
    }

    func finishAll() {
        finishCurrent()
        flushTask?.cancel()
        flushTask = nil
        flush()
    }

    private func finishCurrent() {
        guard !currentItemId.isEmpty else { return }
        let watchMs = max(0, Int((Date().timeIntervalSince1970 - currentStartedAt) * 1000))
        let itemId = currentItemId
        currentItemId = ""
        if watchMs < 800 || currentProgress < 0.06 {
            enqueue(itemId, "skip", watchMs: watchMs)
        } else {
            enqueue(
                itemId,
                "watch",
                watchMs: watchMs,
                durationMs: currentDurationMs,
                progress: currentProgress,
                completed: currentCompleted
            )
        }
        scheduleFlush()
    }

    private func enqueue(
        _ itemId: String,
        _ type: String,
        watchMs: Int? = nil,
        durationMs: Int? = nil,
        progress: Double? = nil,
        completed: Bool? = nil
    ) {
        pending.append(VideoKernelFeedbackEvent(
            eventId: sessionId + ":" + UUID().uuidString,
            itemId: itemId,
            type: type,
            at: dateFormatter.string(from: Date()),
            watchMs: watchMs,
            durationMs: durationMs,
            progress: progress,
            completed: completed,
            source: "video-tab"
        ))
        if pending.count > 240 {
            pending.removeFirst(pending.count - 240)
        }
    }

    private func scheduleFlush() {
        guard flushTask == nil, !pending.isEmpty else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            self?.flushTask = nil
            self?.flush()
        }
    }

    private func flush() {
        guard !sending, !pending.isEmpty else { return }
        let batch = Array(pending.prefix(60))
        pending.removeFirst(batch.count)
        sending = true
        Task { [weak self] in
            let accepted = await API.shared.feedEvents(batch)
            guard let self else { return }
            self.sending = false
            if !accepted {
                self.pending.insert(contentsOf: batch, at: 0)
                if self.pending.count > 240 {
                    self.pending.removeLast(self.pending.count - 240)
                }
            }
            if !self.pending.isEmpty {
                self.scheduleFlush()
            }
        }
    }
}
