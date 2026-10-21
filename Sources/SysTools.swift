import SwiftUI

enum SysPage: String, Identifiable {
    case tools, support, kefu, security, devices, safety, feedback, delete
    var id: String { rawValue }
}

struct SysTeamMenuBar: View {
    var onTools: () -> Void
    var onKefu: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            button(Tr("自助工具"), onTools)
            Rectangle().fill(C.hairline).frame(width: 0.5, height: 22)
            button(Tr("联系客服"), onKefu)
        }
        .frame(height: 44)
        .background(C.cardBg)
        .overlay(alignment: .top) { HairLine() }
    }

    private func button(_ t: String, _ tap: @escaping () -> Void) -> some View {
        Button { tap() } label: {
            Text(t)
                .font(pf(15))
                .foregroundColor(C.label)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct SysToolsView: View {
    @Environment(\.dismiss) private var dismiss

    var onPick: (String) -> Void

    private let items: [(key: String, icon: String, title: String, sub: String)] = [
        ("pwd",     "lock.rotation",        "修改登录密码",   "改完别的设备要重新登录"),
        ("devices", "iphone.gen3",          "登录设备管理",   "看有谁登录过你的号，可以踢掉"),
        ("support", "questionmark.circle",  "找回密码",       "查看找回流程或联系人工客服"),
        ("safety",  "snowflake",            "冻结账号",       "怀疑被盗，先冻住不让别人登"),
        ("safety",  "sun.max",              "解冻账号",       "已经冻结过的号，申请解冻"),
        ("delete",  "xmark.circle",         "注销账号",       "不用了？注销前先看清数据说明"),
        ("feedback","bubble.left",          "意见反馈",       "提交问题并查看处理结果")
    ]

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: Tr("自助工具"), back: { dismiss() })

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    HStack {
                        Text(Tr("账号相关的事，在这儿自己办或者找客服"))
                            .font(pf(12.5)).foregroundColor(C.subLabel)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)

                    VStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.offset) { i, it in
                            if i > 0 { HairLine(inset: 56) }
                            Button { onPick(it.key) } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: it.icon)
                                        .font(.system(size: 17))
                                        .foregroundColor(C.green)
                                        .frame(width: 28)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(Tr(it.title)).font(pf(15.5)).foregroundColor(C.label)
                                        Text(Tr(it.sub)).font(pf(12)).foregroundColor(C.subLabel)
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: 6)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(C.subLabel)
                                }
                                .padding(.horizontal, 16).frame(height: 58)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .background(C.cardBg)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.horizontal, 12)

                    Spacer().frame(height: 30)
                }
            }
            .background(C.pageBg)
        }
        .background(C.pageBg.ignoresSafeArea(edges: .top))
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .hidesTabBar()
    }
}
