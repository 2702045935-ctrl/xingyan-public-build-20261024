import Foundation
import AVFoundation
import ObjectiveC

private var chrisLoaderKey: UInt8 = 0
extension AVPlayerItem {
    fileprivate var chrisLoader: StreamLoader? {
        get { objc_getAssociatedObject(self, &chrisLoaderKey) as? StreamLoader }
        set { objc_setAssociatedObject(self, &chrisLoaderKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
}

final class StreamHub: NSObject, URLSessionDataDelegate, URLSessionDelegate {
    static let shared = StreamHub()

    private var session: URLSession!
    private let lock = NSLock()
    private var owners: [Int: StreamLoader] = [:]

    private override init() {
        super.init()
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 20
        cfg.timeoutIntervalForResource = 900
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.httpMaximumConnectionsPerHost = 6
        session = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
    }

    func start(_ r: URLRequest) -> URLSessionDataTask {
        session.dataTask(with: r)
    }

    func bind(_ task: URLSessionDataTask, _ owner: StreamLoader) {
        lock.lock(); owners[task.taskIdentifier] = owner; lock.unlock()
    }

    private func owner(_ task: URLSessionTask) -> StreamLoader? {
        lock.lock(); defer { lock.unlock() }
        return owners[task.taskIdentifier]
    }

    private func unbind(_ task: URLSessionTask) -> StreamLoader? {
        lock.lock(); defer { lock.unlock() }
        return owners.removeValue(forKey: task.taskIdentifier)
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        owner(dataTask)?.received(response: response, task: dataTask)
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        owner(dataTask)?.received(data: data, task: dataTask)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        unbind(task)?.completed(task: task, error: error)
    }
}

final class StreamLoader: NSObject, AVAssetResourceLoaderDelegate {
    static let scheme = "chrisplay"

    let queue = DispatchQueue(label: "chris.stream.loader")
    private let token: String
    private let lock = NSLock()
    private var entries: [Int: Entry] = [:]

    private final class Entry {
        let req: AVAssetResourceLoadingRequest
        var task: URLSessionDataTask?
        var done = false
        init(req: AVAssetResourceLoadingRequest) { self.req = req }
    }

    init(token: String) {
        self.token = token
        super.init()
    }

    static func fakeURL(_ u: URL) -> URL? {
        guard var c = URLComponents(url: u, resolvingAgainstBaseURL: false) else { return nil }
        c.scheme = scheme
        return c.url
    }

    static func realURL(_ u: URL) -> URL? {
        guard var c = URLComponents(url: u, resolvingAgainstBaseURL: false) else { return nil }
        c.scheme = "https"
        return c.url
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        guard let fake = loadingRequest.request.url, let real = StreamLoader.realURL(fake) else { return false }
        var r = URLRequest(url: real)
        r.httpMethod = "GET"
        if !token.isEmpty { r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

        if let dr = loadingRequest.dataRequest {
            if dr.requestsAllDataToEndOfResource {
                r.setValue("bytes=\(dr.requestedOffset)-", forHTTPHeaderField: "Range")
            } else if dr.requestedLength > 0 {
                let end = dr.requestedOffset + Int64(dr.requestedLength) - 1
                r.setValue("bytes=\(dr.requestedOffset)-\(end)", forHTTPHeaderField: "Range")
            }
        }
        let e = Entry(req: loadingRequest)
        let task = StreamHub.shared.start(r)
        e.task = task
        lock.lock(); entries[task.taskIdentifier] = e; lock.unlock()
        StreamHub.shared.bind(task, self)
        task.resume()
        return true
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        var victim: Entry?
        lock.lock()
        if let k = entries.first(where: { $0.value.req === loadingRequest })?.key {
            victim = entries.removeValue(forKey: k)
        }
        lock.unlock()
        victim?.task?.cancel()
    }

    func cancelAll() {
        lock.lock()
        let tasks = entries.values.compactMap { $0.task }
        for e in entries.values { e.done = true }
        entries.removeAll()
        lock.unlock()
        tasks.forEach { $0.cancel() }
    }

    fileprivate func received(response: URLResponse, task: URLSessionDataTask) {
        lock.lock()
        let e = entries[task.taskIdentifier]
        lock.unlock()
        guard let e = e, !e.done, !e.req.isCancelled else { return }
        let http = response as? HTTPURLResponse
        let code = http?.statusCode ?? 0
        if code >= 400 {
            finish(e, error: NSError(domain: "chris.stream", code: code,
                                     userInfo: [NSLocalizedDescriptionKey: "HTTP \(code)"]))
            return
        }
        if let ci = e.req.contentInformationRequest {
            let mime = response.mimeType ?? ""
            if !mime.isEmpty { ci.contentType = mime }

            let isPlaylist = mime.contains("mpegurl") || (e.req.request.url?.pathExtension == "m3u8")
            ci.isByteRangeAccessSupported = !isPlaylist
                && (code == 206 || ((http?.value(forHTTPHeaderField: "Accept-Ranges") ?? "").contains("bytes")))
            ci.contentLength = StreamLoader.totalLength(http: http, response: response)
        }

        if e.req.dataRequest == nil { finish(e, error: nil) }
    }

    fileprivate func received(data: Data, task: URLSessionDataTask) {
        lock.lock()
        let e = entries[task.taskIdentifier]
        lock.unlock()
        guard let e = e, !e.done, !e.req.isCancelled else { return }
        e.req.dataRequest?.respond(with: data)
    }

    fileprivate func completed(task: URLSessionTask, error: Error?) {
        lock.lock()
        let e = entries.removeValue(forKey: task.taskIdentifier)
        lock.unlock()
        guard let e = e, !e.done else { return }
        if e.req.isCancelled { e.done = true; return }
        finish(e, error: error)
    }

    private func finish(_ e: Entry, error: Error?) {
        lock.lock()
        let wasDone = e.done
        e.done = true
        entries.removeValue(forKey: e.task?.taskIdentifier ?? -1)
        lock.unlock()
        guard !wasDone else { return }
        if let err = error { e.req.finishLoading(with: err) } else { e.req.finishLoading() }
    }

    private static func totalLength(http: HTTPURLResponse?, response: URLResponse) -> Int64 {
        if let cr = http?.value(forHTTPHeaderField: "Content-Range"),
           let tail = cr.split(separator: "/").last, let n = Int64(tail) {
            return n
        }
        if response.expectedContentLength > 0 { return response.expectedContentLength }
        return -1
    }
}

enum StreamPlay {

    private static var keepAlive: [StreamLoader] = []
    private static let keepLock = NSLock()

    static func makeAsset(_ url: URL) -> AVURLAsset? {
        guard let fake = StreamLoader.fakeURL(url) else { return nil }
        let loader = StreamLoader(token: API.shared.token)
        let asset = AVURLAsset(url: fake)
        asset.resourceLoader.setDelegate(loader, queue: loader.queue)
        keep(loader)
        return asset
    }

    static func item(_ url: URL) -> AVPlayerItem? {
        guard let fake = StreamLoader.fakeURL(url) else { return nil }
        let loader = StreamLoader(token: API.shared.token)
        let asset = AVURLAsset(url: fake)
        asset.resourceLoader.setDelegate(loader, queue: loader.queue)
        keep(loader)
        let it = AVPlayerItem(asset: asset)
        it.chrisLoader = loader
        return it
    }

    static func cancel(_ item: AVPlayerItem?) {
        item?.chrisLoader?.cancelAll()
    }

    static func player(_ url: URL) -> AVPlayer? {
        guard let it = item(url) else { return nil }
        let p = AVPlayer(playerItem: it)
        p.actionAtItemEnd = .none

        p.automaticallyWaitsToMinimizeStalling = false
        p.currentItem?.preferredForwardBufferDuration = 1.5
        return p
    }

    static func download(_ url: URL, preferLocal: Bool = true) async -> URL? {
        if preferLocal, let local = LocalStore.localURL(url.path),
           FileManager.default.fileExists(atPath: local.path) {
            return local
        }
        guard url.scheme == "http" || url.scheme == "https" else { return url }

        var req = URLRequest(url: url)
        req.timeoutInterval = 120
        req.setValue(AppInfo.build, forHTTPHeaderField: "X-App-Build")
        if !API.shared.token.isEmpty { req.setValue("Bearer \(API.shared.token)", forHTTPHeaderField: "Authorization") }
        guard let (tmp, resp) = try? await API.shared.session.download(for: req) else { return nil }
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 { return nil }
        let ext = url.pathExtension.isEmpty ? "mp4" : url.pathExtension
        let dst = FileManager.default.temporaryDirectory
            .appendingPathComponent("chris-dl-\(UUID().uuidString).\(ext)")
        try? FileManager.default.removeItem(at: dst)
        guard (try? FileManager.default.moveItem(at: tmp, to: dst)) != nil else { return nil }
        if let d = try? Data(contentsOf: dst) {
            LocalStore.keep(url.path, data: d)
        }
        return dst
    }

    private static func keep(_ l: StreamLoader) {
        keepLock.lock()
        keepAlive.append(l)

        keepLock.unlock()
    }
}
