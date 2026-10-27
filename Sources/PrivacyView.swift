import SwiftUI

struct PrivacyView: View {
    @ObservedObject private var lang = LangStore.shared
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var p = PrivacySettings()
    @State private var showRange = false

    var body: some View {
        List {
            Section {
                row(Tr("加我为朋友时需要验证"), $p.needVerify, "needVerify")
                row(Tr("允许陌生人查看朋友圈"), $p.strangerMoments, "strangerMoments")
                Button {
                    showRange = true
                } label: {
                    HStack {
                        Text(Tr("朋友圈可见范围"))
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(rangeLabel)
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
            }

            Section(header: Text(Tr("添加我的方式")),
                    footer: Text(Tr("关掉之后，别人就不能用这个方式找到你、加你好友。"))) {
                row(Tr("账号"), $p.addByWx, "addByWx")
                row(Tr("手机号"), $p.addByPhone, "addByPhone")
                row(Tr("群聊"), $p.addByGroup, "addByGroup")
                row(Tr("二维码"), $p.addByQR, "addByQR")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Tr("隐私"))
        .hidesTabBar()
        .task { p = await API.shared.privacy() }
        .confirmationDialog(Tr("朋友圈可见范围"), isPresented: $showRange, titleVisibility: .visible) {
            Button(Tr("最近三天")) { setRange("3d") }
            Button(Tr("最近半年")) { setRange("6m") }
            Button(Tr("全部")) { setRange("all") }
            Button(Tr("取消"), role: .cancel) { }
        }
    }

    private var rangeLabel: String {
        switch p.momentsRange {
        case "3d": return Tr("最近三天")
        case "6m": return Tr("最近半年")
        default: return Tr("全部")
        }
    }

    private func setRange(_ v: String) {
        p.momentsRange = v
        Task { await API.shared.setPrivacyText("momentsRange", v) }
    }

    private func row(_ title: String, _ value: Binding<Bool>, _ key: String) -> some View {
        Toggle(isOn: Binding(
                get: { value.wrappedValue },
                set: { v in
                    value.wrappedValue = v
                    Task { await API.shared.setPrivacy(key, v) }
                }
            )) {
                Text(title)
            }
    }
}

struct NotifyView: View {
    @ObservedObject private var lang = LangStore.shared
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var n = NotifySettings()
    @State private var muteOn = false
    @ObservedObject private var push = PushCenter.shared

    private var sysText: String { push.authorized ? Tr("已开启") : Tr("已关闭") }

    var body: some View {
        List {
            Section {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack {
                        Text(Tr("接收新消息通知"))
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(sysText)
                            .foregroundStyle(push.authorized ? Color.secondary : Color.red)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
            }

            Section {
                row(Tr("App 内提醒"), $n.on, "on")
                row(Tr("声音"), $n.sound, "sound")
                row(Tr("振动"), $n.vibrate, "vibrate")
                row(Tr("通知显示消息详情"), $n.showDetail, "showDetail")
            } footer: {
                if !push.authorized {
                    Text(Tr("系统通知还没开：点上面那行去 iOS 设置里打开「允许通知」，不然 App 在后台收不到提醒。"))
                }
            }

            Section {
                Toggle(Tr("免打扰"), isOn: $muteOn)
                if muteOn {
                    DatePicker(Tr("开始"),
                               selection: Binding(
                                get: { Self.time(n.muteStart, 22, 0) },
                                set: { n.muteStart = Self.hhmm($0) }),
                               displayedComponents: .hourAndMinute)
                    DatePicker(Tr("结束"),
                               selection: Binding(
                                get: { Self.time(n.muteEnd, 7, 0) },
                                set: { n.muteEnd = Self.hhmm($0) }),
                               displayedComponents: .hourAndMinute)
                }
            } footer: {
                Text(Tr("免打扰时段里收到消息不响不震，进 App 还是能看到小红点。"))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Tr("通知"))
        .hidesTabBar()
        .task {
            n = await API.shared.notifySettings()
            muteOn = !(n.muteStart.isEmpty || n.muteEnd.isEmpty)
            if !muteOn { n.muteStart = ""; n.muteEnd = "" }
            PushCenter.shared.start()
        }
        .onChange(of: muteOn) { on in
            if on { n.muteStart = "22:00"; n.muteEnd = "07:00" }
            else { n.muteStart = ""; n.muteEnd = "" }
            Task { await API.shared.setNotify(["muteStart": n.muteStart, "muteEnd": n.muteEnd]) }
        }
    }

    private func row(_ title: String, _ value: Binding<Bool>, _ key: String) -> some View {
        Toggle(isOn: Binding(
                get: { value.wrappedValue },
                set: { v in
                    value.wrappedValue = v
                    Task { await API.shared.setNotify([key: v]) }
                }
            )) {
                Text(title)
            }
    }

    static func hhmm(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: d)
    }
    static func time(_ s: String, _ h: Int, _ m: Int) -> Date {
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        if let d = f.date(from: s) { return d }
        var c = DateComponents(); c.hour = h; c.minute = m
        return Calendar.current.date(from: c) ?? Date()
    }
}

struct GeneralView: View {
    @ObservedObject private var lang = LangStore.shared
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var showTheme = false
    @State private var showLang = false
    @State private var showBg = false
    @State private var showBgPick = false
    @State private var showStorage = false
    @State private var showHistory = false
    @State private var showVoice = false
    @ObservedObject private var voiceStore = VoiceChangerStore.shared

    var body: some View {
        List {
            Section {
                link(Tr("外观"),
                     app.appearance == "dark" ? Tr("深色")
                         : (app.appearance == "light" ? Tr("浅色") : Tr("跟随系统")),
                     key: "g.theme")
                link(Tr("界面语言"), Lang.name, key: "g.lang")
                link(Tr("聊天背景"),
                     (app.me?.chatBackground ?? "auto") == "auto" ? Tr("恢复默认") : Tr("自定义"),
                     key: "g.chatbg")
            }
            Section {
                link(Tr("存储空间"), "", key: "g.storage")
                link(Tr("聊天记录管理"), "", key: "g.history")
                link(Tr("语音变声"), voiceStore.current.name, key: "g.voice")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Tr("通用"))
        .hidesTabBar()
    }

    private func link(_ title: String, _ value: String, key: String) -> some View {
        NavigationLink(value: key) {
            LabeledContent {
                Text(value)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } label: {
                Text(title)
                    .foregroundStyle(.primary)
            }
        }
    }

    private func row(_ title: String, _ value: String, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            LabeledContent {
                Text(value)
                    .foregroundStyle(.secondary)
            } label: {
                Text(title)
                    .foregroundStyle(.primary)
            }
        }
    }

    private func setLang(_ code: String) {
        Lang.code = code
        app.show(code == "en" ? "Language switched to English" : "界面语言已切成中文")
        dismiss()

    }

    private func changeBg(_ image: UIImage) {
        Task {
            if let url = try? await API.shared.uploadOriginal(image: image) {
                await API.shared.changeBackground(url)
                app.me = try? await API.shared.me()
                app.show(Tr("聊天背景换好了"))
            }
        }
    }
}

struct AppearanceView: View {
    @ObservedObject private var lang = LangStore.shared
    @EnvironmentObject var app: AppState

    private let opts: [(String, String)] = [("auto", "跟随系统"), ("light", "浅色"), ("dark", "深色")]

    var body: some View {
        List {
            Section {
                ForEach(opts.indices, id: \.self) { i in
                    Button {
                        app.setAppearance(opts[i].0)
                    } label: {
                        HStack {
                            Text(Tr(opts[i].1))
                                .foregroundStyle(.primary)
                            Spacer()
                            if app.appearance == opts[i].0 {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Tr("外观"))
        .hidesTabBar()
    }
}

struct LanguageView: View {
    @ObservedObject private var lang = LangStore.shared
    @EnvironmentObject var app: AppState

    private let opts: [(String, String)] = [("zh", "简体中文"), ("en", "English")]

    var body: some View {
        List {
            Section {
                ForEach(opts.indices, id: \.self) { i in
                    Button {
                        Lang.code = opts[i].0
                        app.show(opts[i].0 == "en" ? "Language switched to English"
                                                   : "界面语言已切成中文")
                    } label: {
                        HStack {
                            Text(opts[i].1)
                                .foregroundStyle(.primary)
                            Spacer()
                            if Lang.code == opts[i].0 {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            } footer: {
                Text(Tr("换完语言把 App 从后台划掉重开，全部界面文字才是新语言。"))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Tr("界面语言"))
        .hidesTabBar()
    }
}

struct PrivacySettings {
    var needVerify = true
    var strangerMoments = false
    var addByWx = true
    var addByPhone = true
    var addByGroup = true
    var addByQR = true

    var momentsRange = "all"
}

struct NotifySettings {
    var on = true
    var sound = true
    var vibrate = true
    var showDetail = true
    var muteStart = ""
    var muteEnd = ""
}
