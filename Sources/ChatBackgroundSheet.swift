import SwiftUI
import UIKit

final class ChatBgStore: ObservableObject {
    static let shared = ChatBgStore()

    @Published private(set) var version = 0

    private func key(_ chatId: String) -> String { "chris.chatBg." + chatId }

    func get(_ chatId: String) -> String {
        guard !chatId.isEmpty else { return "" }
        return UserDefaults.standard.string(forKey: key(chatId)) ?? ""
    }

    func set(_ chatId: String, _ value: String) {
        guard !chatId.isEmpty else { return }
        if value.isEmpty || value == "auto" {
            UserDefaults.standard.removeObject(forKey: key(chatId))
        } else {
            UserDefaults.standard.set(value, forKey: key(chatId))
        }
        version += 1
    }
}

struct ChatBackgroundSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    var chatId: String = ""

    @State private var picking = false
    @State private var busy = false

    static let presets: [String] = ["/bg/bw1.jpg", "/bg/bw2.jpg", "/bg/bw3.jpg",
                                    "/bg/bw4.jpg", "/bg/bw5.jpg", "/bg/bw6.jpg"]

    static let names: [String] = ["流光晨雾", "深空石墨", "雾蓝丝绸", "苔原微光", "烟粉云霞", "黑曜星砂"]

    @State private var remotePresets: [ChatBgPayload.Item] = []
    @State private var remoteVersion = ""

    private var shownPresets: [(path: String, name: String)] {
        let remote = remotePresets.compactMap { it -> (path: String, name: String)? in
            guard let p = it.path, !p.isEmpty else { return nil }
            return (p, it.name ?? "")
        }
        if !remote.isEmpty { return remote }
        var out: [(path: String, name: String)] = []
        for (idx, p) in Self.presets.enumerated() {
            out.append((p, Self.names[min(idx, Self.names.count - 1)]))
        }
        return out
    }

    private func versioned(_ p: String) -> String {
        guard !remoteVersion.isEmpty, !p.hasPrefix("data:") else { return p }
        return p + (p.contains("?") ? "&" : "?") + "v=" + remoteVersion
    }

    private var inChat: Bool { !chatId.isEmpty }
    @ObservedObject private var store = ChatBgStore.shared

    private var current: String {
        if inChat {
            let synced = app.me?.chatBackgrounds?[chatId] ?? ""
            let v = synced.isEmpty ? store.get(chatId) : synced
            return v.isEmpty ? "auto" : v
        }
        return app.me?.chatBackground ?? "auto"
    }

    var body: some View {

        VStack(spacing: 0) {
            NavBar(title: Tr(inChat ? "选择背景图" : "聊天背景"), back: { dismiss() }) {
                Button { dismiss() } label: {
                    Text(Tr("完成")).font(pf(15.5)).foregroundColor(C.label)
                        .padding(.horizontal, 14).frame(height: 32)
                }
                .buttonStyle(.plain)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(Tr("基础背景 · 黑白场景"))
                        .font(pf(13))
                        .foregroundColor(C.subLabel)
                        .padding(.horizontal, 16)
                        .padding(.top, 6)

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                              spacing: 12) {

                        ForEach(Array(shownPresets.enumerated()), id: \.offset) { _, item in
                            Button { pick(item.path, cacheKey: versioned(item.path)) } label: {
                                VStack(spacing: 5) {
                                    ZStack {
                                        RemoteImage(path: versioned(item.path), mode: .fill)
                                            .frame(maxWidth: .infinity)
                                            .frame(height: 148)
                                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        if current == item.path {
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .stroke(C.green, lineWidth: 2.5)
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.system(size: 19))
                                                .foregroundColor(C.green)
                                                .padding(5)
                                                .frame(maxWidth: .infinity, maxHeight: .infinity,
                                                       alignment: .topTrailing)
                                        }
                                    }
                                    if !item.name.isEmpty {
                                        Text(Tr(item.name))
                                            .font(pf(11.5))
                                            .foregroundColor(C.subLabel)
                                            .lineLimit(1)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)

                    Rectangle().fill(C.pageBg).frame(height: 8).padding(.top, 12)

                    VStack(spacing: 0) {
                        Button { pick("auto") } label: {
                            HStack {
                                Text(inChat ? Tr("使用全局背景") : Tr("默认背景"))
                                    .font(pf(16)).foregroundColor(C.label)
                                Spacer(minLength: 0)
                                if current == "auto" {
                                    Image(systemName: "checkmark").foregroundColor(C.green)
                                }
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 52)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .disabled(busy)

                        HairLine(inset: 16)

                        Button { picking = true } label: {
                            HStack {
                                Text(Tr("从相册选一张")).font(pf(16)).foregroundColor(C.label)
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(C.subLabel)
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 52)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .disabled(busy)
                    }
                    .background(C.cardBg)

                    if busy {
                        HStack { Spacer(); ProgressView(); Spacer() }.padding(.top, 14)
                    }
                }
                .padding(.bottom, 26)
            }
            .background(C.pageBg)
        }
        .background(C.pageBg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
        .sheet(isPresented: $picking) {
            PhotoPicker { image in upload(image) }
        }

        .task { await loadRemote() }
    }

    private func loadRemote() async {
        guard let r = await API.shared.chatBackgrounds() else { return }
        remotePresets = r.presets ?? []
        remoteVersion = r.version ?? ""

        if let def = r.default, !def.isEmpty, (app.me?.chatBackground ?? "auto") == "auto" {
            app.defaultChatBackground = def
        }
    }

    private func pick(_ path: String, cacheKey: String = "") {

        primeBackgroundCache(path: path, cacheKey: cacheKey)
        if inChat {
            let oldUser = app.me
            let oldLocal = ChatBgStore.shared.get(chatId)
            applyChatBackground(path)
            Task {
                busy = true
                if let saved = await API.shared.changeChatBackground(chatId: chatId, path: path) {
                    applySyncedChatBackgrounds(saved)
                    app.show(path == "auto" ? Tr("已改用全局背景") : Tr("这个聊天的背景换好了"))
                } else {
                    app.me = oldUser
                    ChatBgStore.shared.set(chatId, oldLocal)
                    app.show(Tr("背景没保存上，检查网络"))
                }
                busy = false
            }
            return
        }
        if var me = app.me {
            me.chatBackground = path
            app.me = me
        }
        Task {
            busy = true
            await API.shared.changeBackground(path)
            if path == "auto" {
                app.show(Tr("已恢复默认背景"))
            }
            busy = false
        }
    }

    private func upload(_ image: UIImage) {
        Task {
            busy = true
            if let url = try? await API.shared.uploadOriginal(image: image) {
                primeBackgroundCache(path: url, image: image)
                if inChat {
                    if let saved = await API.shared.changeChatBackground(chatId: chatId, path: url) {
                        applyChatBackground(url)
                        applySyncedChatBackgrounds(saved)
                        app.show(Tr("这个聊天的背景换好了"))
                    } else {
                        app.show(Tr("图片上传失败，换一张再试"))
                    }
                } else {
                    if var me = app.me {
                        me.chatBackground = url
                        app.me = me
                    }
                    await API.shared.changeBackground(url)
                    app.show(Tr("聊天背景换好了"))
                }
            } else {
                app.show(Tr("图片上传失败，换一张再试"))
            }
            busy = false
        }
    }

    private func applyChatBackground(_ path: String) {
        ChatBgStore.shared.set(chatId, path)
        guard var me = app.me else { return }
        var map = me.chatBackgrounds ?? [:]
        if path == "auto" {
            map.removeValue(forKey: chatId)
        } else {
            map[chatId] = path
        }
        me.chatBackgrounds = map
        app.me = me
    }

    private func applySyncedChatBackgrounds(_ map: [String: String]) {
        guard var me = app.me else { return }
        me.chatBackgrounds = map.filter { !$0.value.isEmpty && $0.value != "auto" }
        app.me = me
    }

    private func primeBackgroundCache(path: String, cacheKey: String = "", image: UIImage? = nil) {
        guard !path.isEmpty, path != "auto" else { return }
        if let image = image {
            ImageStore.shared.put(path, image)
            if let data = image.jpegData(compressionQuality: 0.86) {
                Task.detached(priority: .userInitiated) { ImageStore.shared.diskWrite(path, data) }
            }
            return
        }
        guard !cacheKey.isEmpty, cacheKey != path else { return }
        if let cached = ImageStore.shared.get(cacheKey) {
            ImageStore.shared.put(path, cached)
            return
        }
        if let data = ImageStore.shared.diskRead(cacheKey),
           let image = RemoteImage.downsampled(data, maxSide: 1600) {
            ImageStore.shared.put(path, image)
            Task.detached(priority: .userInitiated) { ImageStore.shared.diskWrite(path, data) }
        }
    }
}
