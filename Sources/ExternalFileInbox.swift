import SwiftUI
import UIKit
import Foundation

struct ExternalFileItem: Identifiable {
    let id = UUID()
    let name: String
    let local: URL
    let bytes: Int
}

/// WPS / 文件 App 通过“用其他应用打开”送进来的文件先落到这里，
/// 再由 ExternalFileSendView 选择会话并走聊天原生的文件上传接口。
final class ExternalFileInbox: ObservableObject {
    static let shared = ExternalFileInbox()

    @Published var files: [ExternalFileItem] = []
    @Published var present = false
    @Published var importing = false

    private init() {}

    func accept(_ urls: [URL]) {
        let valid = urls.filter { $0.isFileURL }
        guard !valid.isEmpty else { return }
        DispatchQueue.main.async { self.importing = true }

        DispatchQueue.global(qos: .userInitiated).async {
            var copied: [ExternalFileItem] = []
            let fm = FileManager.default
            let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("ExternalInbox", isDirectory: true)
            try? fm.createDirectory(at: base, withIntermediateDirectories: true)

            for source in valid {
                let scoped = source.startAccessingSecurityScopedResource()
                defer { if scoped { source.stopAccessingSecurityScopedResource() } }

                let rawName = source.lastPathComponent.isEmpty ? "文件" : source.lastPathComponent
                let name = Self.safeName(rawName)
                var destination = base.appendingPathComponent(name)
                if fm.fileExists(atPath: destination.path) {
                    let stem = destination.deletingPathExtension().lastPathComponent
                    let ext = destination.pathExtension
                    destination = base.appendingPathComponent(
                        stem + "-" + String(Int(Date().timeIntervalSince1970)) + (ext.isEmpty ? "" : "." + ext))
                }
                do {
                    try fm.copyItem(at: source, to: destination)
                    let attrs = try? fm.attributesOfItem(atPath: destination.path)
                    let size = (attrs?[.size] as? NSNumber)?.intValue ?? 0
                    copied.append(ExternalFileItem(name: destination.lastPathComponent,
                                                   local: destination,
                                                   bytes: size))
                } catch {
                    /* 有些提供商给的是临时 URL；直接读字节再落盘更稳。 */
                    if let data = try? Data(contentsOf: source), !data.isEmpty {
                        do {
                            try data.write(to: destination, options: .atomic)
                            copied.append(ExternalFileItem(name: destination.lastPathComponent,
                                                           local: destination,
                                                           bytes: data.count))
                        } catch {
                        }
                    }
                }
            }

            DispatchQueue.main.async {
                self.importing = false
                if copied.isEmpty { return }
                self.files.append(contentsOf: copied)
                self.present = true
            }
        }
    }

    func finish() {
        let old = files
        files = []
        present = false
        for item in old { try? FileManager.default.removeItem(at: item.local) }
    }

    private static func safeName(_ raw: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:")
        var name = raw.components(separatedBy: bad).joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { name = "文件" }
        if name.count > 180 { name = String(name.prefix(180)) }
        return name
    }
}

struct ExternalFileSendView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var inbox: ExternalFileInbox
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var selectedId = ""
    @State private var choosingForward = false
    @State private var favoriteBusy = false
    @State private var sending = false
    @State private var progress = ""
    @State private var alert = ""

    private var chats: [Chat] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let rows = app.chats.filter { $0.oaId == nil && $0.oaDigest != true }
        guard !q.isEmpty else { return rows }
        return rows.filter { $0.name.lowercased().contains(q) }
    }

    private var selected: Chat? { app.chats.first { $0.id == selectedId } }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                fileCard
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                if !choosingForward {
                    VStack(spacing: 10) {
                        actionRow(title: Tr("转发给朋友"), icon: "paperplane.fill",
                                  tint: Color(hex: 0x1AAD6A)) {
                            choosingForward = true
                        }
                        actionRow(title: Tr("收藏"), icon: "star.fill",
                                  tint: Color(hex: 0xE3A126)) {
                            favorite()
                        }
                    }
                    .padding(16)

                    if favoriteBusy {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text(progress).font(.system(size: 12.5)).foregroundColor(C.subLabel)
                        }
                        .padding(.top, 2)
                    }
                    Spacer()
                } else {
                    HStack(spacing: 7) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(C.subLabel)
                        TextField(Tr("搜索联系人"), text: $query)
                            .font(.system(size: 14))
                        if !query.isEmpty {
                            Button { query = "" } label: {
                                Image(systemName: "xmark.circle.fill").foregroundColor(C.subLabel)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                    .background(C.fieldBg)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .padding(12)

                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 0) {
                            ForEach(chats) { chat in
                                chatRow(chat)
                                if chat.id != chats.last?.id { HairLine(inset: 64) }
                            }
                        }
                    }

                    if sending {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text(progress).font(.system(size: 12.5)).foregroundColor(C.subLabel)
                        }
                        .padding(.vertical, 10)
                    }

                    Button { send() } label: {
                        Text(sending ? Tr("发送中…") : (selectedId.isEmpty ? Tr("选择一个聊天") : Tr("发送")))
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(selectedId.isEmpty ? C.subLabel : C.green))
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedId.isEmpty || sending)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
            }
            .background(C.pageBg.ignoresSafeArea())
            .navigationTitle(choosingForward ? Tr("发送给") : Tr("文件"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(Tr("取消")) {
                        if !sending { inbox.finish() }
                    }
                }
            }
            .task { if app.chats.isEmpty { await app.loadChats() } }
            .alert(alert, isPresented: Binding(get: { !alert.isEmpty },
                                               set: { if !$0 { alert = "" } })) {
                Button(Tr("知道了"), role: .cancel) {}
            }
        }
    }

    private var fileCard: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(C.green.opacity(0.12))
                    .frame(width: 42, height: 42)
                Image(systemName: "doc.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(C.green)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(inbox.files.count == 1 ? inbox.files[0].name
                     : Tr("\(inbox.files.count) 个文件"))
                    .font(.system(size: 14.5, weight: .medium))
                    .foregroundColor(C.label)
                    .lineLimit(1)
                Text(fileBytes)
                    .font(.system(size: 11))
                    .foregroundColor(C.subLabel)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(C.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private var fileBytes: String {
        let total = inbox.files.reduce(0) { $0 + $1.bytes }
        if total <= 0 { return Tr("准备发送") }
        if total < 1024 * 1024 { return String(format: "%.1f KB", Double(total) / 1024.0) }
        return String(format: "%.1f MB", Double(total) / 1024.0 / 1024.0)
    }

    private func actionRow(title: String, icon: String, tint: Color,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(tint)
                    .frame(width: 42, height: 42)
                    .background(tint.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(C.label)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(C.arrow)
            }
            .padding(.horizontal, 13)
            .frame(height: 62)
            .background(C.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(favoriteBusy)
    }

    private func chatRow(_ chat: Chat) -> some View {
        Button {
            selectedId = chat.id
        } label: {
            HStack(spacing: 11) {
                Group {
                    if let path = chat.avatar, !path.isEmpty {
                        RemoteImage(path: path, icon: "person.fill", mode: .fill)
                    } else {
                        Image(systemName: chat.type == "group" ? "person.3.fill" : "person.fill")
                            .font(.system(size: 18))
                            .foregroundColor(C.subLabel)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(C.fieldBg)
                    }
                }
                .frame(width: 42, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                Text(chat.name)
                    .font(.system(size: 15))
                    .foregroundColor(C.label)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: selectedId == chat.id ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19))
                    .foregroundColor(selectedId == chat.id ? C.green : C.subLabel.opacity(0.45))
            }
            .padding(.horizontal, 16)
            .frame(height: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func send() {
        guard let chat = selected, !inbox.files.isEmpty else { return }
        sending = true
        Task {
            var done = 0
            for item in inbox.files {
                progress = Tr("正在上传") + " \(done + 1)/\(inbox.files.count)"
                guard let data = try? Data(contentsOf: item.local), !data.isEmpty else { continue }
                if data.count > 80 * 1024 * 1024 {
                    alert = Tr("单个文件不能超过 80MB")
                    break
                }
                do {
                    let up = try await uploadItem(item, data: data)
                    let contentObject: [String: Any] = [
                        "url": up.url,
                        "name": item.name,
                        "bytes": data.count
                    ]
                    let body = try JSONSerialization.data(withJSONObject: contentObject, options: [])
                    let content = String(data: body, encoding: .utf8) ?? "{\"url\":\"\(up.url)\"}"
                    _ = try await API.shared.send(chatId: chat.id, kind: "file", content: content)
                    done += 1
                } catch {
                    alert = (error as? APIError)?.errorDescription ?? Tr("文件发送失败")
                    break
                }
            }
            sending = false
            if alert.isEmpty && done > 0 {
                await app.loadChats()
                inbox.finish()
                dismiss()
            }
        }
    }

    private func favorite() {
        guard !inbox.files.isEmpty else { return }
        favoriteBusy = true
        Task {
            var lines: [String] = []
            var done = 0
            for item in inbox.files {
                progress = Tr("正在收藏") + " \(done + 1)/\(inbox.files.count)"
                guard let data = try? Data(contentsOf: item.local), !data.isEmpty else { continue }
                if data.count > 80 * 1024 * 1024 {
                    alert = Tr("单个文件不能超过 80MB")
                    break
                }
                do {
                    let up = try await uploadItem(item, data: data)
                    lines.append(item.name + "\n" + up.url)
                    done += 1
                } catch {
                    alert = (error as? APIError)?.errorDescription ?? Tr("收藏失败")
                    break
                }
            }
            if alert.isEmpty && done > 0 {
                let title = inbox.files.count == 1 ? inbox.files[0].name
                    : Tr("\(inbox.files.count) 个文件")
                let ok = await API.shared.addFavorite(kind: "text",
                                                      content: lines.joined(separator: "\n\n"),
                                                      title: title,
                                                      from: "外部文件")
                if ok {
                    app.show(Tr("已收藏"))
                    inbox.finish()
                    dismiss()
                } else {
                    alert = Tr("收藏失败")
                }
            }
            favoriteBusy = false
        }
    }

    private func uploadItem(_ item: ExternalFileItem,
                            data: Data) async throws -> (url: String, name: String, bytes: Int) {
        try await API.shared.rawUpload([
            "dataUrl": "data:application/octet-stream;base64," + data.base64EncodedString(),
            "filename": item.name
        ])
    }
}
