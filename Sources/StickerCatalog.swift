import Foundation
import SwiftUI

struct RemoteStickerPack: Decodable, Hashable, Identifiable {
    var id: String
    var name: String
    var category: String

    var dir: String

    var icon: String
    var files: [String]

    var paths: [String] { files.map { dir + "/" + $0 } }
}

struct StickerCategory: Decodable, Hashable, Identifiable {
    var id: String
    var name: String
}

private struct StickerCatalogPayload: Decodable {
    var categories: [StickerCategory]?
    var packs: [RemoteStickerPack]?
}

@MainActor
final class StickerCatalog: ObservableObject {
    static let shared = StickerCatalog()

    @Published private(set) var categories: [StickerCategory] = []
    @Published private(set) var packs: [RemoteStickerPack] = []
    @Published private(set) var loading = false
    private var loaded = false

    func loadIfNeeded() async {
        if loaded || loading { return }
        loading = true
        defer { loading = false }
        guard let url = API.shared.assetURL("emoji/packs.json"),
              let data = try? await API.shared.assetData(url),
              let p = try? JSONDecoder().decode(StickerCatalogPayload.self, from: data) else { return }
        categories = p.categories ?? []
        packs = p.packs ?? []
        loaded = true
    }

    func packs(in category: String) -> [RemoteStickerPack] {
        packs.filter { $0.category == category }
    }

    func search(_ keyword: String) -> [RemoteStickerPack] {
        let k = keyword.trimmingCharacters(in: .whitespaces)
        guard !k.isEmpty else { return packs }
        return packs.filter { $0.name.localizedCaseInsensitiveContains(k) }
    }
}

struct PanelPack: Identifiable {
    let id: String
    let name: String

    let icon: String

    let stickers: [String]
    let isImage: Bool
}
