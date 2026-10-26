import SwiftUI

struct FavoriteNoteComposeSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    let editingId: String

    let initial: String

    let onSaved: () -> Void

    @State private var text = ""
    @State private var busy = false
    @State private var msg = ""
    @FocusState private var focused: Bool

    @State private var showPic = false
    @State private var picBusy = false

    @State private var pics: [String] = []

    init(editingId: String = "", initial: String = "", onSaved: @escaping () -> Void) {
        self.editingId = editingId
        self.initial = initial
        self.onSaved = onSaved

        var body: [String] = []
        var imgs: [String] = []
        for line in initial.components(separatedBy: "\n") {
            if line.hasPrefix("[图]") { imgs.append(String(line.dropFirst(3))) }
            else { body.append(line) }
        }
        _text = State(initialValue: body.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines))
        _pics = State(initialValue: imgs)
    }

    private var canSave: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pics.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: editingId.isEmpty ? Tr("写笔记") : Tr("编辑笔记"), back: { dismiss() }) {
                Button { Task { await save() } } label: {
                    Text(busy ? Tr("保存中…") : Tr("保存"))
                        .font(pf(15, .medium))
                        .foregroundColor(canSave ? C.green : C.subLabel)
                        .padding(.horizontal, 14).frame(height: 32)
                }
                .buttonStyle(.plain)
                .disabled(busy || !canSave)
            }

            VStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text(Tr("写点什么…（最多 2 万字）"))
                            .font(pf(16)).foregroundColor(C.subLabel)
                            .padding(.horizontal, 14).padding(.top, 12)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $text)
                        .font(pf(16))
                        .foregroundColor(C.label)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 10).padding(.top, 4)
                        .focused($focused)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                if !pics.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
                        ForEach(pics, id: \.self) { p in
                            ZStack(alignment: .topTrailing) {
                                RemoteImage(path: p, mode: .fill, maxSide: 600)
                                    .frame(height: 92)
                                    .frame(maxWidth: .infinity)
                                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                                Button { pics.removeAll { $0 == p } } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 17))
                                        .foregroundColor(.white)
                                        .shadow(color: .black.opacity(0.35), radius: 1.5)
                                        .padding(4)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
                    .padding(.bottom, 10)
                }
            }
            .background(C.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.top, 12)

            HStack(spacing: 10) {
                Button { showPic = true } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "photo").font(.system(size: 14))
                        Text(Tr("插入图片")).font(pf(13.5))
                    }
                    .foregroundColor(C.green)
                    .padding(.horizontal, 12).frame(height: 32)
                    .background(Capsule().fill(C.cardBg))
                }
                .buttonStyle(.plain)
                .disabled(picBusy)

                Button {
                    text += "\n————————\n"
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "minus").font(.system(size: 14))
                        Text(Tr("分割线")).font(pf(13.5))
                    }
                    .foregroundColor(C.green)
                    .padding(.horizontal, 12).frame(height: 32)
                    .background(Capsule().fill(C.cardBg))
                }
                .buttonStyle(.plain)

                if picBusy { ProgressView().scaleEffect(0.7) }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.top, 8)

            HStack(spacing: 10) {
                if !msg.isEmpty {
                    Text(msg).font(pf(12.5)).foregroundColor(C.subLabel)
                }
                Spacer(minLength: 0)
                Text(String(text.count) + " / 20000")
                    .font(pf(12)).foregroundColor(C.subLabel)
            }
            .padding(.horizontal, 16).padding(.top, 8)

            Spacer(minLength: 0)
        }
        .background(C.pageBg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .task { DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { focused = true } }
        .sheet(isPresented: $showPic) {
            PhotoPicker { img in insertImage(img) }
        }
    }

    private func insertImage(_ img: UIImage) {
        picBusy = true
        Task {
            do {
                let url = try await API.shared.upload(image: img)
                pics.append(url)
                msg = Tr("图片已插入")
            } catch {
                msg = (error as? APIError)?.errorDescription ?? "图片上传失败"
            }
            picBusy = false
        }
    }

    private func save() async {

        var body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !pics.isEmpty {
            let imgs = pics.map { "[图]" + $0 }.joined(separator: "\n")
            body = body.isEmpty ? imgs : (body + "\n" + imgs)
        }
        guard !body.isEmpty else { return }
        busy = true
        msg = ""

        let firstLine = body.split(separator: "\n").first.map(String.init) ?? body
        let title = String(firstLine.prefix(24))

        let ok: Bool
        if editingId.isEmpty {
            ok = await API.shared.addFavorite(kind: "text", content: body, title: title, from: "")
        } else {
            ok = await API.shared.updateFavorite(id: editingId, content: body, title: title)
        }
        busy = false
        if ok {
            DiagLog.shared.note("收藏：保存了一条笔记（" + String(body.count) + " 字）")
            onSaved()
            dismiss()
        } else {
            msg = Tr("保存失败，再试一次")
        }
    }
}

struct FavoriteNoteDetailSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    let id: String
    let content: String

    var pinned: Bool = false

    let onChanged: () -> Void

    @State private var editing = false
    @State private var copied = false
    @State private var isPinned = false
    @State private var showForward = false

    @State private var viewerPath: String?

    private var hasPic: Bool {
        content.components(separatedBy: "\n").contains { $0.hasPrefix("[图]") }
    }

    private var lines: [String] {
        content.components(separatedBy: "\n")
    }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("笔记"), back: { dismiss() }) {
                Button {
                    UIPasteboard.general.string = content
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                } label: {
                    Text(copied ? Tr("已复制") : Tr("复制"))
                        .font(pf(15, .medium)).foregroundColor(C.green)
                        .padding(.horizontal, 14).frame(height: 32)
                }
                .buttonStyle(.plain)
            }

            ScrollView(showsIndicators: false) {

                VStack(alignment: .leading, spacing: 8) {
                    if content.isEmpty {
                        Text(Tr("（空）")).font(pf(16)).foregroundColor(C.subLabel)
                    } else {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                            if line.hasPrefix("[图]") {
                                let path = String(line.dropFirst(3))
                                NoteImageBlock(path: path) { p in viewerPath = p }
                            } else if !line.isEmpty {
                                Text(line)
                                    .font(pf(16))
                                    .foregroundColor(C.label)
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
                .padding(14)
                .background(C.cardBg)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 12)
                .padding(.top, 12)

                VStack(spacing: 0) {

                    Button { Task { await pin(!isPinned) } } label: {
                        HStack(spacing: 10) {
                            Image(systemName: isPinned ? "pin.slash" : "pin").font(.system(size: 15))
                            Text(isPinned ? Tr("取消置顶") : Tr("置顶")).font(pf(16))
                            Spacer(minLength: 0)
                        }
                        .foregroundColor(C.label)
                        .padding(.horizontal, 16).frame(height: 52)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    HairLine(inset: 16)

                    Button { showForward = true } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "arrowshape.turn.up.right").font(.system(size: 15))
                            Text(Tr("转发给朋友")).font(pf(16))
                            Spacer(minLength: 0)
                        }
                        .foregroundColor(C.label)
                        .padding(.horizontal, 16).frame(height: 52)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    HairLine(inset: 16)
                    Button { editing = true } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "square.and.pencil").font(.system(size: 15))
                            Text(Tr("编辑这条笔记")).font(pf(16))
                            Spacer(minLength: 0)
                        }
                        .foregroundColor(C.label)
                        .padding(.horizontal, 16).frame(height: 52)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    HairLine(inset: 16)
                    Button { Task { await remove() } } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "trash").font(.system(size: 15))
                            Text(Tr("删除")).font(pf(16))
                            Spacer(minLength: 0)
                        }
                        .foregroundColor(C.red)
                        .padding(.horizontal, 16).frame(height: 52)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .background(C.cardBg)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 12)
                .padding(.top, 10)
                Spacer().frame(height: 30)
            }
            .background(C.pageBg)
        }
        .background(C.pageBg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .overlay {
            if let p = viewerPath, !p.isEmpty {
                PhotoPager(paths: [p], startIndex: 0, showActions: true) { viewerPath = nil }
            }
        }
        .task { isPinned = pinned }

        .sheet(isPresented: $showForward) {

            ForwardPickerView(items: [ForwardItem(kind: hasPic ? "note" : "text", content: content)]) { }
                .environmentObject(app)
        }
        .sheet(isPresented: $editing) {
            FavoriteNoteComposeSheet(editingId: id, initial: content) {
                onChanged()
                dismiss()
            }
            .environmentObject(app)
        }
    }

    private func pin(_ on: Bool) async {
        if await API.shared.updateFavorite(id: id, pinned: on) {
            isPinned = on
            DiagLog.shared.note(on ? "收藏：置顶了一条" : "收藏：取消置顶")
            onChanged()
        }
    }

    private func remove() async {
        await API.shared.deleteFavorite(id)
        DiagLog.shared.note("收藏：删掉了一条笔记")
        onChanged()
        dismiss()
    }
}
