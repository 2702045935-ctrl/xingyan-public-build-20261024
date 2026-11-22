import CryptoKit
import Foundation
import Security

enum TransferUploaderError: LocalizedError {
    case unsupported
    case invalidFile(String)
    case http(Int, String)
    case network(String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .unsupported:
            return "服务器暂不支持分片传输"
        case .invalidFile(let message):
            return message
        case .http(_, let message):
            return message.isEmpty ? "上传失败，请检查网络后再试" : message
        case .network:
            return "网络中断，上传进度已经保留，可以继续"
        case .badResponse:
            return "上传返回异常"
        }
    }

    var isUnsupported: Bool {
        if case .unsupported = self { return true }
        return false
    }

    var allowsLegacyFallback: Bool {
        switch self {
        case .unsupported, .badResponse:
            return true
        case .http(let status, _):
            return [404, 405, 426, 500, 501, 502, 503, 504].contains(status)
        default:
            return false
        }
    }

    var isRetryable: Bool {
        switch self {
        case .network:
            return true
        case .http(let status, _):
            return status == 408 || status == 425 || status == 429 || status >= 500
        default:
            return false
        }
    }
}

private struct TransferEnvelope<T: Decodable>: Decodable {
    var data: T?
}

private struct TransferWireError: Decodable {
    var error: String?
}

private struct TransferInitEnvelope: Decodable {
    var transfer: TransferRemoteState
}

private struct TransferCompleteEnvelope: Decodable {
    var transfer: TransferRemoteState
}

private struct TransferRemoteState: Decodable {
    var id: String
    var status: String
    var size: Int64
    var chunkSize: Int
    var totalChunks: Int
    var receivedBytes: Int64
    var received: [Int]
    var missing: [Int]
    var url: String
    var error: String
}

private struct TransferStoredJob: Codable {
    var key: String
    var remoteId: String
    var base: String
    var size: Int64
    var sha256: String
    var updatedAt: Date
}

final class TransferBackgroundSession: NSObject, URLSessionDataDelegate, URLSessionTaskDelegate {
    static let shared = TransferBackgroundSession()

    private let lock = NSLock()
    private var continuations: [Int: CheckedContinuation<(Data, HTTPURLResponse), Error>] = [:]
    private var progressHandlers: [Int: (Double) -> Void] = [:]
    private var responseData: [Int: Data] = [:]
    private var backgroundEventsCompletion: (() -> Void)?

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(
            withIdentifier: "com.chris.chatnative.transfer"
        )
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 180
        config.timeoutIntervalForResource = 86_400
        config.httpMaximumConnectionsPerHost = 3
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    func upload(_ request: URLRequest,
                bodyFile: URL,
                onProgress: @escaping (Double) -> Void) async throws -> (Data, HTTPURLResponse) {
        let task = session.uploadTask(with: request, fromFile: bodyFile)
        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            continuations[task.taskIdentifier] = continuation
            progressHandlers[task.taskIdentifier] = onProgress
            responseData[task.taskIdentifier] = Data()
            lock.unlock()
            task.resume()
        }
    }

    func stage(_ data: Data) throws -> URL {
        let root = FileManager.default.urls(for: .cachesDirectory,
                                            in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = root.appendingPathComponent("StarTransferChunks", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("chunk-\(UUID().uuidString.lowercased())")
        try data.write(to: file, options: .atomic)
        return file
    }

    func handleEventsCompletion(_ completion: @escaping () -> Void) {
        lock.lock()
        backgroundEventsCompletion = completion
        lock.unlock()
    }

    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition,
                                                  URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            if ServerTrustPolicy.canAccept(trust, host: challenge.protectionSpace.host) {
                completionHandler(.useCredential, URLCredential(trust: trust))
            } else {
                completionHandler(.cancelAuthenticationChallenge, nil)
            }
            return
        }
        completionHandler(.performDefaultHandling, nil)
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64,
                    totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        lock.lock()
        let handler = progressHandlers[task.taskIdentifier]
        lock.unlock()
        handler?(min(1, max(0, Double(totalBytesSent) / Double(totalBytesExpectedToSend))))
    }

    func urlSession(_ session: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive data: Data) {
        lock.lock()
        responseData[dataTask.taskIdentifier, default: Data()].append(data)
        lock.unlock()
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        lock.lock()
        let continuation = continuations.removeValue(forKey: task.taskIdentifier)
        let progress = progressHandlers.removeValue(forKey: task.taskIdentifier)
        let data = responseData.removeValue(forKey: task.taskIdentifier) ?? Data()
        lock.unlock()
        progress?(1)
        guard let continuation else { return }
        if let error {
            continuation.resume(throwing: error)
            return
        }
        guard let response = task.response as? HTTPURLResponse else {
            continuation.resume(throwing: TransferUploaderError.badResponse)
            return
        }
        continuation.resume(returning: (data, response))
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        lock.lock()
        let completion = backgroundEventsCompletion
        backgroundEventsCompletion = nil
        lock.unlock()
        if let completion {
            DispatchQueue.main.async(execute: completion)
        }
    }
}

private final class TransferProgressBox {
    private let lock = NSLock()
    private let total: Int64
    private let onProgress: (Double) -> Void
    private var completed: Int64
    private var partial: [Int: Int64] = [:]

    init(completed: Int64, total: Int64, onProgress: @escaping (Double) -> Void) {
        self.completed = completed
        self.total = max(1, total)
        self.onProgress = onProgress
    }

    func update(index: Int, sent: Int64) {
        lock.lock()
        partial[index] = max(0, sent)
        let current = completed + partial.values.reduce(0, +)
        lock.unlock()
        onProgress(min(0.995, Double(current) / Double(total)))
    }

    func finish(index: Int, bytes: Int64) {
        lock.lock()
        partial[index] = nil
        completed += max(0, bytes)
        let current = completed
        lock.unlock()
        onProgress(min(0.995, Double(current) / Double(total)))
    }
}

private final class TransferJobStore {
    static let shared = TransferJobStore()

    private let lock = NSLock()
    private let fileURL: URL?
    private var rows: [String: TransferStoredJob] = [:]

    private init() {
        let root = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first
        if let root {
            let dir = root.appendingPathComponent("StarTransfer", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir,
                                                     withIntermediateDirectories: true)
            fileURL = dir.appendingPathComponent("jobs.json")
        } else {
            fileURL = nil
        }
        load()
    }

    func job(for key: String) -> TransferStoredJob? {
        lock.lock()
        defer { lock.unlock() }
        guard let row = rows[key],
              Date().timeIntervalSince(row.updatedAt) < 7 * 86_400 else {
            rows.removeValue(forKey: key)
            persistLocked()
            return nil
        }
        return row
    }

    func save(_ row: TransferStoredJob) {
        lock.lock()
        defer { lock.unlock() }
        rows[row.key] = row
        let cutoff = Date().addingTimeInterval(-7 * 86_400)
        rows = rows.filter { $0.value.updatedAt >= cutoff }
        persistLocked()
    }

    func remove(_ key: String) {
        lock.lock()
        defer { lock.unlock() }
        rows.removeValue(forKey: key)
        persistLocked()
    }

    private func load() {
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([TransferStoredJob].self, from: data) else {
            return
        }
        rows = Dictionary(uniqueKeysWithValues: decoded.map { ($0.key, $0) })
    }

    private func persistLocked() {
        guard let fileURL,
              let data = try? JSONEncoder().encode(Array(rows.values)) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

final class TransferUploader {
    static let shared = TransferUploader()

    private init() {}

    func uploadFile(_ file: URL,
                    mime: String,
                    skipTranscode: Bool,
                    base: String,
                    token: String,
                    session: URLSession,
                    onProgress: @escaping (Double) -> Void) async throws -> String {
        let values = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values?.isRegularFile == true, let fileSize = values?.fileSize, fileSize > 0 else {
            throw TransferUploaderError.invalidFile("读不到这个文件")
        }
        let fingerprint = try await Task.detached(priority: .userInitiated) {
            try Self.fileFingerprint(file)
        }.value
        guard fingerprint.size == Int64(fileSize) else {
            throw TransferUploaderError.invalidFile("文件在上传前发生了变化")
        }
        let name = file.lastPathComponent.isEmpty ? "file" : file.lastPathComponent
        return try await uploadPrepared(
            size: fingerprint.size,
            sha256: fingerprint.sha256,
            name: name,
            mime: mime,
            skipTranscode: skipTranscode,
            base: base,
            token: token,
            session: session,
            readChunk: { index, length in
                let handle = try FileHandle(forReadingFrom: file)
                defer { try? handle.close() }
                try handle.seek(toOffset: UInt64(index * length))
                guard let data = try handle.read(upToCount: length), !data.isEmpty else {
                    throw TransferUploaderError.invalidFile("读取文件分片失败")
                }
                return data
            },
            onProgress: onProgress
        )
    }

    func uploadData(_ data: Data,
                    name: String,
                    mime: String,
                    skipTranscode: Bool,
                    base: String,
                    token: String,
                    session: URLSession,
                    onProgress: @escaping (Double) -> Void) async throws -> String {
        guard !data.isEmpty else {
            throw TransferUploaderError.invalidFile("文件内容为空")
        }
        let sha = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return try await uploadPrepared(
            size: Int64(data.count),
            sha256: sha,
            name: name,
            mime: mime,
            skipTranscode: skipTranscode,
            base: base,
            token: token,
            session: session,
            readChunk: { index, length in
                let start = index * length
                let end = min(data.count, start + length)
                guard start < end else {
                    throw TransferUploaderError.invalidFile("读取上传分片失败")
                }
                return data.subdata(in: start..<end)
            },
            onProgress: onProgress
        )
    }

    private func uploadPrepared(
        size: Int64,
        sha256: String,
        name: String,
        mime: String,
        skipTranscode: Bool,
        base: String,
        token: String,
        session: URLSession,
        readChunk: @escaping (Int, Int) throws -> Data,
        onProgress: @escaping (Double) -> Void
    ) async throws -> String {
        let key = "\(base)|\(size)|\(sha256)|\(name)"
        let existing = TransferJobStore.shared.job(for: key)
        var remote: TransferRemoteState

        var reusable: TransferRemoteState?
        if let existing {
            do {
                if let resumed = try await fetchStatus(id: existing.remoteId,
                                                       base: base,
                                                       token: token,
                                                       session: session,
                                                       allowMissing: true),
                   resumed.status != "corrupt",
                   resumed.status != "failed",
                   resumed.status != "cancelled" {
                    reusable = resumed
                } else {
                    TransferJobStore.shared.remove(key)
                }
            } catch {
                // A job created before a server rollout can be unreadable by
                // the new endpoint. It is safe to discard only the local
                // pointer; acknowledged chunks remain authoritative remotely.
                TransferJobStore.shared.remove(key)
            }
        }
        if let reusable {
            remote = reusable
        } else {
            remote = try await initialize(size: size,
                                          sha256: sha256,
                                          name: name,
                                          mime: mime,
                                          skipTranscode: skipTranscode,
                                          base: base,
                                          token: token,
                                          session: session)
        }

        if remote.status == "ready", !remote.url.isEmpty {
            onProgress(1)
            return remote.url
        }

        TransferJobStore.shared.save(TransferStoredJob(
            key: key,
            remoteId: remote.id,
            base: base,
            size: size,
            sha256: sha256,
            updatedAt: Date()
        ))

        let progress = TransferProgressBox(
            completed: remote.receivedBytes,
            total: size,
            onProgress: onProgress
        )
        progress.update(index: -1, sent: 0)
        let pending = remote.missing
        let workerCount = min(3, pending.count)
        if workerCount > 0 {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for worker in 0..<workerCount {
                    group.addTask {
                        var position = worker
                        while position < pending.count {
                            let index = pending[position]
                            let offset = Int64(index) * Int64(remote.chunkSize)
                            let length = Int(min(Int64(remote.chunkSize), size - offset))
                            let chunk = try readChunk(index, length)
                            guard chunk.count == length else {
                                throw TransferUploaderError.invalidFile("文件分片长度不正确")
                            }
                            let chunkHash = SHA256.hash(data: chunk)
                                .map { String(format: "%02x", $0) }
                                .joined()
                            try await self.putChunk(
                                id: remote.id,
                                index: index,
                                sha256: chunkHash,
                                body: chunk,
                                base: base,
                                token: token,
                                session: session,
                                onChunkProgress: { fraction in
                                    progress.update(
                                        index: index,
                                        sent: Int64(fraction * Double(chunk.count))
                                    )
                                }
                            )
                            progress.finish(index: index, bytes: Int64(chunk.count))
                            position += workerCount
                        }
                    }
                }
                try await group.waitForAll()
            }
        }

        let url = try await complete(id: remote.id,
                                     base: base,
                                     token: token,
                                     session: session)
        TransferJobStore.shared.save(TransferStoredJob(
            key: key,
            remoteId: remote.id,
            base: base,
            size: size,
            sha256: sha256,
            updatedAt: Date()
        ))
        onProgress(1)
        return url
    }

    private func initialize(size: Int64,
                            sha256: String,
                            name: String,
                            mime: String,
                            skipTranscode: Bool,
                            base: String,
                            token: String,
                            session: URLSession) async throws -> TransferRemoteState {
        let body: [String: Any] = [
            "size": size,
            "sha256": sha256,
            "name": name,
            "mime": mime,
            "skipTranscode": skipTranscode
        ]
        let data = try JSONSerialization.data(withJSONObject: body)
        let (responseData, response) = try await send(path: "/api/transfer/init",
                                                      method: "POST",
                                                      body: data,
                                                      contentType: "application/json",
                                                      base: base,
                                                      token: token,
                                                      session: session)
        guard response.statusCode != 404, response.statusCode != 405 else {
            throw TransferUploaderError.unsupported
        }
        guard (200...299).contains(response.statusCode) else {
            throw wireError(responseData, status: response.statusCode)
        }
        guard let envelope = try? JSONDecoder().decode(
            TransferEnvelope<TransferInitEnvelope>.self,
            from: responseData
        ), let state = envelope.data?.transfer else {
            throw TransferUploaderError.badResponse
        }
        return state
    }

    private func fetchStatus(id: String,
                             base: String,
                             token: String,
                             session: URLSession,
                             allowMissing: Bool) async throws -> TransferRemoteState? {
        let (data, response) = try await send(path: "/api/transfer/\(id)",
                                              method: "GET",
                                              body: nil,
                                              contentType: nil,
                                              base: base,
                                              token: token,
                                              session: session)
        if allowMissing, response.statusCode == 404 { return nil }
        guard (200...299).contains(response.statusCode) else {
            throw wireError(data, status: response.statusCode)
        }
        guard let envelope = try? JSONDecoder().decode(
            TransferEnvelope<TransferInitEnvelope>.self,
            from: data
        ), let state = envelope.data?.transfer else {
            throw TransferUploaderError.badResponse
        }
        return state
    }

    private func putChunk(id: String,
                          index: Int,
                          sha256: String,
                          body: Data,
                          base: String,
                          token: String,
                          session: URLSession,
                          onChunkProgress: @escaping (Double) -> Void) async throws {
        var lastError: Error?
        let bodyFile = try TransferBackgroundSession.shared.stage(body)
        defer { try? FileManager.default.removeItem(at: bodyFile) }
        for attempt in 0..<4 {
            do {
                guard let url = URL(string: base + "/api/transfer/\(id)/chunk") else {
                    throw TransferUploaderError.badResponse
                }
                var request = URLRequest(url: url)
                request.httpMethod = "PUT"
                request.timeoutInterval = 120
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
                request.setValue(String(index), forHTTPHeaderField: "x-transfer-chunk-index")
                request.setValue(sha256, forHTTPHeaderField: "x-transfer-chunk-sha256")
                let (data, http) = try await TransferBackgroundSession.shared.upload(
                    request,
                    bodyFile: bodyFile,
                    onProgress: onChunkProgress
                )
                guard (200...299).contains(http.statusCode) else {
                    throw wireError(data, status: http.statusCode)
                }
                return
            } catch {
                lastError = error
                let retryable = (error as? TransferUploaderError)?.isRetryable == true
                    || (error as? URLError) != nil
                guard retryable, attempt < 3 else { throw error }
                try await Task.sleep(nanoseconds: UInt64(350_000_000 * (attempt + 1)))
            }
        }
        throw lastError ?? TransferUploaderError.network("上传失败")
    }

    private func complete(id: String,
                          base: String,
                          token: String,
                          session: URLSession) async throws -> String {
        var lastError: Error?
        for attempt in 0..<4 {
            do {
                let (data, response) = try await send(
                    path: "/api/transfer/\(id)/complete",
                    method: "POST",
                    body: Data("{}".utf8),
                    contentType: "application/json",
                    base: base,
                    token: token,
                    session: session
                )
                guard (200...299).contains(response.statusCode) else {
                    throw wireError(data, status: response.statusCode)
                }
                guard let envelope = try? JSONDecoder().decode(
                    TransferEnvelope<TransferCompleteEnvelope>.self,
                    from: data
                ), let url = envelope.data?.transfer.url, !url.isEmpty else {
                    throw TransferUploaderError.badResponse
                }
                return url
            } catch {
                lastError = error
                let retryable = (error as? TransferUploaderError)?.isRetryable == true
                    || (error as? URLError) != nil
                guard retryable, attempt < 3 else { throw error }
                try await Task.sleep(nanoseconds: UInt64(450_000_000 * (attempt + 1)))
            }
        }
        throw lastError ?? TransferUploaderError.network("上传完成确认失败")
    }

    private func send(path: String,
                      method: String,
                      body: Data?,
                      contentType: String?,
                      base: String,
                      token: String,
                      session: URLSession) async throws -> (Data, HTTPURLResponse) {
        guard let url = URL(string: base + path) else {
            throw TransferUploaderError.badResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 90
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        if let body { request.httpBody = body }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw TransferUploaderError.badResponse
            }
            return (data, http)
        } catch let error as TransferUploaderError {
            throw error
        } catch {
            throw TransferUploaderError.network(error.localizedDescription)
        }
    }

    private func wireError(_ data: Data, status: Int) -> TransferUploaderError {
        let message = (try? JSONDecoder().decode(TransferWireError.self, from: data))?.error ?? ""
        return .http(status, message)
    }

    private static func fileFingerprint(_ file: URL) throws -> (size: Int64, sha256: String) {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        var size: Int64 = 0
        while true {
            let data = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if data.isEmpty { break }
            size += Int64(data.count)
            hasher.update(data: data)
        }
        let sha = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return (size, sha)
    }
}
