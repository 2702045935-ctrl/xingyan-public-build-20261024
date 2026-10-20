import Foundation

enum SearchHistory {
    private static let key = "chris.searchHistory"
    private static let max = 20

    static var all: [String] {
        (UserDefaults.standard.array(forKey: key) as? [String]) ?? []
    }

    static func add(_ word: String) {
        let w = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard w.count >= 1 else { return }
        var list = all.filter { $0 != w }
        list.insert(w, at: 0)
        if list.count > max { list = Array(list.prefix(max)) }
        UserDefaults.standard.set(list, forKey: key)
    }

    static func remove(_ word: String) {
        UserDefaults.standard.set(all.filter { $0 != word }, forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

enum SearchSuggest {

    static let fallback = ["生活圈", "聊天记录", "公众号", "视频号", "附近的人", "群聊"]

    static var remote: [String] = []

    static var shown: [String] {
        let r = remote.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return r.isEmpty ? fallback : r
    }
}
