import Foundation

enum FileUploadStaging {
    /// 通过文件协调器复制到 App 自己的临时目录，兼容 iCloud 和第三方文件提供器。
    nonisolated static func copyToTemporary(_ source: URL) throws -> URL {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(
            "chris-file-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = (try? source.resourceValues(forKeys: [.nameKey]).name)
            ?? source.lastPathComponent
        let dst = dir.appendingPathComponent(name.isEmpty ? "file" : name)

        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: source, options: .withoutChanges,
                                       error: &coordinationError) { readable in
            do {
                try fm.copyItem(at: readable, to: dst)
            } catch {
                copyError = error
            }
        }
        if let copyError {
            try? fm.removeItem(at: dir)
            throw copyError
        }
        if !fm.fileExists(atPath: dst.path) {
            try? fm.removeItem(at: dir)
            if let coordinationError { throw coordinationError }
            throw CocoaError(.fileReadUnknown)
        }
        return dst
    }
}
