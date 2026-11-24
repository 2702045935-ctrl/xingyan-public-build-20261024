import SwiftUI

struct RPCoverEditResult {

    var cover: API.RPCover?
    var deleted: Bool = false
    var makeDefault: Bool = false
}

struct RPCoverEditSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    let cover: API.RPCover?

    let isDefault: Bool
    let onDone: (RPCoverEditResult) -> Void

    @State private var name = ""
    @State private var image = ""
    @State private var thumb = ""
    @State private var color = "#B3241C"
    @State private var enabled = true
    @State private var makeDefault = false
    @State private var showPic = false
    @State private var busy = false
    @State private var msg = ""

    private let colors: [(String, String)] = [
        ("#B3241C", "大红"), ("#8E1412", "酒红"), ("#C9A227", "金"),
        ("#0E332E", "墨绿"), ("#1B5FD0", "宝蓝"), ("#5B2C87", "紫"), ("#111111", "黑")
    ]

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: cover == nil ? Tr("新增红包封面") : Tr("改红包封面"), back: { dismiss() }) {
                Button { Task { await save() } } label: {
                    Text(busy ? Tr("保存中…") : Tr("保存"))
                        .font(pf(15, .medium))
                        .foregroundColor(image.isEmpty ? C.subLabel : C.green)
                        .padding(.horizontal, 14).frame(height: AppDesign.Control.smallButtonHeight)
                }
                .buttonStyle(.plain)
                .disabled(busy || image.isEmpty)
            }

            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {

                    GroupCard {
                        Button { showPic = true } label: {
                            HStack(spacing: AppDesign.Spacing.sm) {
                                Text(Tr("封面图")).font(pf(16)).foregroundColor(C.label)
                                Spacer(minLength: 0)
                                ZStack {
                                    RoundedRectangle(cornerRadius: AppDesign.Radius.small, style: .continuous)
                                        .fill(Color(hexString: color, fallback: 0xB3241C))
                                    if image.isEmpty {
                                        Image(systemName: "photo")
                                            .font(.system(size: 16)).foregroundColor(.white.opacity(0.85))
                                    } else {
                                        RemoteImage(path: thumb.isEmpty ? image : thumb)
                                            .frame(width: 52, height: 66)
                                            .clipShape(RoundedRectangle(cornerRadius: AppDesign.Radius.small, style: .continuous))
                                    }
                                }
                                .frame(width: 52, height: 66)
                                Chevron(size: 9, line: 1.6)
                            }
                            .padding(.horizontal, AppDesign.Spacing.md).frame(height: 84)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        HairLine(inset: 16)
                        HStack(spacing: AppDesign.Spacing.sm) {
                            Text(Tr("名字")).font(pf(16)).foregroundColor(C.label)
                                .frame(width: 62, alignment: .leading)
                            TextField(Tr("金玉满堂"), text: $name)
                                .font(AppDesign.Type.bodyLarge)
                                .multilineTextAlignment(.trailing)
                        }
                        .padding(.horizontal, AppDesign.Spacing.md).frame(height: AppDesign.Control.dialogRowHeight)
                    }
                    .padding(.top, 10)

                    GroupCard(horizontalInset: 0) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(Tr("主题色（发红包页的底色）")).font(pf(13)).foregroundColor(C.subLabel)
                            HStack(spacing: AppDesign.Spacing.sm) {
                                ForEach(colors, id: \.0) { hex, label in
                                    Button { color = hex } label: {
                                        ZStack {
                                            Circle().fill(Color(hexString: hex, fallback: 0xB3241C))
                                                .frame(width: 34, height: 34)
                                            if color.lowercased() == hex.lowercased() {
                                                Circle().stroke(C.green, lineWidth: 2.5).frame(width: 42, height: 42)
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 13, weight: .bold)).foregroundColor(.white)
                                            }
                                        }
                                        .frame(width: 42, height: 42)
                                    }
                                    .buttonStyle(.plain)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                        .padding(.horizontal, AppDesign.Spacing.md).padding(.vertical, 14)

                        HairLine(inset: 16)
                        HStack(spacing: AppDesign.Spacing.sm) {
                            Text(Tr("启用（发红包页能挑到）")).font(pf(16)).foregroundColor(C.label)
                            Spacer(minLength: 0)
                            Toggle("", isOn: $enabled).labelsHidden().tint(C.green)
                        }
                        .padding(.horizontal, AppDesign.Spacing.md).frame(height: AppDesign.Control.menuRowHeight)

                        HairLine(inset: 16)
                        Button { makeDefault.toggle() } label: {
                            HStack(spacing: AppDesign.Spacing.sm) {
                                Text(Tr("设为默认封面")).font(pf(16)).foregroundColor(C.label)
                                Spacer(minLength: 0)
                                Image(systemName: makeDefault ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 20))
                                    .foregroundColor(makeDefault ? C.green : C.subLabel)
                            }
                            .padding(.horizontal, AppDesign.Spacing.md).frame(height: AppDesign.Control.menuRowHeight)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    if cover != nil {
                        Button {
                            onDone(RPCoverEditResult(cover: nil, deleted: true))
                            dismiss()
                        } label: {
                            Text(Tr("删掉这张封面"))
                                .font(pf(16)).foregroundColor(C.red)
                                .frame(maxWidth: .infinity).frame(height: AppDesign.Control.mediumControlHeight)
                        }
                        .buttonStyle(.plain)
                        .background(C.cardBg)
                        .clipShape(RoundedRectangle(cornerRadius: AppDesign.Radius.control, style: .continuous))
                        .padding(.horizontal, AppDesign.Spacing.sm)
                    }

                    if !msg.isEmpty {
                        Text(msg).font(AppDesign.Type.caption).foregroundColor(C.subLabel)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 18)
                    }
                    Spacer().frame(height: AppDesign.Control.sectionHeaderHeight)
                }
            }
            .background(C.pageBg)
        }
        .background(C.pageBg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .sheet(isPresented: $showPic) {
            PhotoPicker { img in upload(img) }
        }
        .task {
            if let c = cover {
                name = c.name ?? ""
                image = c.image ?? ""
                thumb = c.thumb ?? ""
                color = c.color ?? "#B3241C"
                enabled = c.enabled != false
            }
            makeDefault = isDefault
        }
    }

    private func upload(_ img: UIImage) {
        busy = true
        msg = Tr("图片上传中…")
        Task {
            do {
                let url = try await API.shared.upload(image: img)
                image = url
                thumb = url
                msg = Tr("封面已上传")
                if name.isEmpty { name = Tr("新封面") }
            } catch {
                msg = (error as? APIError)?.errorDescription ?? "图片上传失败"
            }
            busy = false
        }
    }

    private func save() async {
        guard !image.isEmpty else { return }
        busy = true
        let c = API.RPCover(id: cover?.id ?? "",
                            name: name.isEmpty ? Tr("红包封面") : name,
                            image: image,
                            thumb: thumb.isEmpty ? image : thumb,
                            color: color,
                            enabled: enabled)
        onDone(RPCoverEditResult(cover: c, deleted: false, makeDefault: makeDefault))
        busy = false
        dismiss()
    }
}
